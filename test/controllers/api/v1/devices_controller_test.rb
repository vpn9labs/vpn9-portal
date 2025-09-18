require "test_helper"

class Api::V1::DevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @relay = relays(:stockholm_relay)
    @redis = FakeRedis.new
    DeviceRegistry.redis = @redis
  end

  teardown do
    DeviceRegistry.redis = nil
  end

  test "should require authentication" do
    post api_v1_devices_url, params: {}, as: :json

    assert_response :unauthorized
    assert_equal "Missing authentication token", json_response["error"]
  end

  test "should create device with valid params" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    public_key = "pubkey-#{SecureRandom.hex(8)}"
    assert_difference -> { @user.devices.count }, +1 do
      post api_v1_devices_url,
           params: {
             device: {
               public_key: public_key,
               name: "desktop-device"
             },
             relay_id: @relay.id
           },
           headers: { "Authorization" => "Bearer #{token}" },
           as: :json
    end

    assert_response :created
    body = json_response

    assert_equal public_key, body.dig("device", "public_key")
    assert_equal "desktop-device", body.dig("device", "name")
    assert_includes [ "active", "inactive" ], body.dig("device", "status")
    assert body.dig("device", "ipv4").present?
    assert body.dig("device", "ipv6").present?
    refute body.key?("config"), "response should not include client config"
    refute body.key?("filename"), "response should not include config filename"

    created_device = @user.devices.find_by(public_key: public_key)
    assert_not_nil created_device
  end

  test "creating a device stores an encrypted preferred relay hint" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    post api_v1_devices_url,
         params: {
           device: {
             public_key: "pref-#{SecureRandom.hex(4)}",
             name: "hint-device"
           },
           relay_id: @relay.id
         },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :created
    device_id = json_response.dig("device", "id")
    refute_nil device_id

    key = "vpn9:device-pref:#{device_id}"
    raw = @redis.get(key)
    refute_nil raw
    refute_equal @relay.id.to_s, raw

    ttl = @redis.ttl(key)
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, DeviceRegistry::DEFAULT_PREFERRED_RELAY_TTL

    assert_equal @relay.id.to_s, DeviceRegistry.consume_preferred_relay(device_id)
    refute @redis.exists?(key)
    assert_nil DeviceRegistry.consume_preferred_relay(device_id)
  end

  test "should enforce device limit" do
    limited_user = users(:john)
    create_active_subscription_for(limited_user, plan: plans(:single_1))

    limited_user.devices.create!(
      name: "limit-test-#{SecureRandom.hex(4)}",
      public_key: "limit-pubkey-#{SecureRandom.hex(6)}"
    )

    token = generate_valid_token_for(limited_user)

    post api_v1_devices_url,
         params: {
           device: { public_key: "new-pubkey-#{SecureRandom.hex(6)}" },
           relay_id: @relay.id
         },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :unprocessable_content
    assert_equal "Device limit reached", json_response["error"]
    assert_equal limited_user.device_limit, json_response["device_limit"]
  end

  test "should reject device creation when user becomes inactive" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)
    @user.update!(status: :locked)

    post api_v1_devices_url,
         params: {
           device: {
             public_key: "pubkey-#{SecureRandom.hex(6)}",
             name: "inactive-device"
           },
           relay_id: @relay.id
         },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :unauthorized
    assert_equal "Invalid or expired token", json_response["error"]
  end

  test "should require relay id" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    post api_v1_devices_url,
         params: {
           device: { public_key: "pubkey-#{SecureRandom.hex(6)}" }
         },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :unprocessable_content
    assert_equal "relay_id is required", json_response["error"]
  end

  test "should reject inactive relay" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    post api_v1_devices_url,
         params: {
           device: { public_key: "pubkey-#{SecureRandom.hex(6)}" },
           relay_id: relays(:uk_relay_inactive).id
         },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :not_found
    assert_equal "Relay not found or inactive", json_response["error"]
  end

  test "should return validation errors for invalid device" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    post api_v1_devices_url,
         params: {
           device: { public_key: "" },
           relay_id: @relay.id
         },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :unprocessable_content
    assert_includes json_response["errors"], "Public key can't be blank"
  end

  test "verify should require authentication" do
    post verify_api_v1_devices_url, params: { public_key: "missing" }, as: :json

    assert_response :unauthorized
    assert_equal "Missing authentication token", json_response["error"]
  end

  test "verify returns device data for matching public key" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)
    device = devices(:another_device)

    post verify_api_v1_devices_url,
         params: { public_key: device.public_key },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :ok
    body = json_response

    assert_equal device.public_key, body.dig("device", "public_key")
    assert_equal device.name, body.dig("device", "name")
    assert body.dig("device", "ipv4").present?
    assert body.dig("device", "ipv6").present?
    refute body.key?("relay"), "verify response should omit relay metadata"
  end

  test "verify returns not found for unknown device" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    post verify_api_v1_devices_url,
         params: { public_key: "nonexistent-pubkey" },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :not_found
    assert_equal "Device not found", json_response["error"]
  end

  test "verify rejects requests from inactive user" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)
    @user.update!(status: :locked)

    post verify_api_v1_devices_url,
         params: { public_key: devices(:another_device).public_key },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :unauthorized
    assert_equal "Invalid or expired token", json_response["error"]
  end

  test "verify does not leak devices from other users" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)
    other_device = devices(:two_device)

    post verify_api_v1_devices_url,
         params: { public_key: other_device.public_key },
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :not_found
    assert_equal "Device not found", json_response["error"]
  end

  test "verify requires public_key parameter" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    post verify_api_v1_devices_url,
         params: {},
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json

    assert_response :bad_request
    assert_match "public_key", json_response["error"]
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def create_active_subscription_for(user, plan: plans(:monthly))
    user.subscriptions.destroy_all
    user.subscriptions.create!(
      plan: plan,
      status: "active",
      started_at: 1.day.ago,
      expires_at: 1.month.from_now
    )
  end

  def generate_valid_token_for(user)
    payload = {
      sub: user.id.to_s,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i,
      subscription_expires: (user.current_subscription&.expires_at || 1.day.from_now).to_i
    }

    private_key = OpenSSL::PKey::RSA.new(Base64.decode64(ENV["JWT_PRIVATE_KEY"]))
    JWT.encode(payload, private_key, "RS256")
  end
end
