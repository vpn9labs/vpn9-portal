require "test_helper"

class DeviceSetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Create and sign in a user
    @user = User.create!(email_address: "device-setup@example.com", password: "password")
    @passphrase = @user.regenerate_passphrase!

    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Common fixtures
    @stockholm = locations(:stockholm)
    @new_york = locations(:new_york)
    @gothenburg = locations(:gothenburg)
    @london = locations(:london)

    @relay_stockholm = relays(:stockholm_relay)
    @relay_se1 = relays(:se_relay_1)
    @relay_se2 = relays(:se_relay_2)
    @relay_gbg_maintenance = relays(:se_relay_3)
    @relay_uk_inactive = relays(:uk_relay_inactive)
  end

  # Authentication
  test "new requires authentication" do
    delete session_path
    get new_device_setup_path
    assert_redirected_to new_session_path
  end

  test "locations requires authentication" do
    delete session_path
    get "/device_setup/locations"
    assert_redirected_to new_session_path
  end

  test "relays requires authentication" do
    delete session_path
    get "/device_setup/relays/#{@stockholm.id}"
    assert_redirected_to new_session_path
  end

  # GET /device_setup/new
  test "new lists only locations with active relays" do
    get new_device_setup_path
    assert_response :success
    assert_select "h3", "Setup New Device"

    # Included (has active relays)
    assert_includes response.body, @stockholm.city
    assert_includes response.body, @new_york.city

    # Excluded (no active relays)
    refute_includes response.body, @gothenburg.city # maintenance only
    refute_includes response.body, @london.city     # inactive only
  end

  test "new redirects when at device limit" do
    # Default limit is 5 with no subscription
    5.times { |i| @user.devices.create!(public_key: "limit_key_#{i}") }

    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit of 5 devices", flash[:alert]
  end

  # POST /device_setup
  test "create persists device and responds with config download" do
    public_key = "wg_pub_key_#{SecureRandom.hex(8)}"
    private_key = "wg_priv_key_#{SecureRandom.hex(8)}"

    assert_difference "Device.count", +1 do
      post device_setup_path, params: {
        device: { public_key: public_key },
        private_key: private_key,
        relay_id: @relay_stockholm.id
      }
    end

    assert_response :success

    # Attachment headers
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "vpn9-"

    # Content type and body
    assert_includes response.content_type, "text/plain"
    assert_includes response.body, "PrivateKey = #{private_key}"
    assert_includes response.body, "PublicKey = #{@relay_stockholm.public_key}"
    assert_includes response.body, "Endpoint = #{@relay_stockholm.ipv4_address}:#{@relay_stockholm.port}"

    created = @user.devices.order(created_at: :desc).first
    assert_equal public_key, created.public_key
  end

  test "create with invalid params re-renders new with 422" do
    assert_no_difference "Device.count" do
      post device_setup_path, params: {
        device: { public_key: "" },
        private_key: "ignored",
        relay_id: @relay_stockholm.id
      }
    end

    assert_response :unprocessable_content
    assert_select "h3", "Setup New Device"
  end

  # GET /device_setup/locations (JSON)
  test "locations endpoint returns only active locations with expected shape" do
    get "/device_setup/locations"
    assert_response :success
    assert_includes response.content_type, "application/json"

    data = JSON.parse(response.body)
    assert_kind_of Array, data

    names = data.map { |h| h["name"] }
    assert_includes names, @stockholm.city
    assert_includes names, @new_york.city
    refute_includes names, @gothenburg.city
    refute_includes names, @london.city

    # Verify keys present on an element
    sample = data.first
    %w[id name country city display_name].each do |key|
      assert sample.key?(key), "expected key #{key} in locations payload"
    end
  end

  # GET /device_setup/relays/:location_id (JSON)
  test "relays endpoint returns only active relays for location" do
    get "/device_setup/relays/#{@stockholm.id}"
    assert_response :success
    assert_includes response.content_type, "application/json"

    data = JSON.parse(response.body)
    assert_kind_of Array, data

    # Stockholm has 3 relays in fixtures, 3 are active for Stockholm (stockholm_relay, se_relay_1, se_relay_2)
    assert_equal 3, data.size

    # Keys present and load value in allowed set
    sample = data.first
    %w[id name hostname public_key port load].each do |key|
      assert sample.key?(key), "expected key #{key} in relays payload"
    end
    assert_includes %w[low medium high], sample["load"]
  end

  test "relays endpoint returns empty array for location without active relays" do
    # London has only an inactive relay in fixtures
    get "/device_setup/relays/#{@london.id}"
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal [], data
  end
end
