require "test_helper"

class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Clear cache before each test to avoid rate limiting issues
    Rails.cache.clear

    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.instance_variable_get(:@issued_passphrase)

    # Create an active subscription for the user
    plan = plans(:monthly)

    @subscription = Subscription.create!(
      user: @user,
      plan: plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )
  end

  test "should authenticate with valid passphrase and return token" do
    post api_v1_token_path, params: {
      passphrase: "#{@passphrase}:password"  # Include password since user was created with one
    }, as: :json

    assert_response :success

    json = JSON.parse(response.body)
    assert json["token"].present?
    assert_equal 86400, json["expires_in"]  # 24 hours
    assert_not_nil json["subscription_expires_at"]
  end

  test "should fail authentication with invalid passphrase" do
    post api_v1_token_path, params: {
      passphrase: "invalid"
    }, as: :json

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "Invalid passphrase", json["error"]
  end

  test "should fail without active subscription" do
    # Remove subscription
    @subscription.destroy

    post api_v1_token_path, params: {
      passphrase: "#{@passphrase}:password"
    }, as: :json

    assert_response :payment_required
    json = JSON.parse(response.body)
    assert_equal "No active subscription", json["error"]
    assert json["subscription_required"]
  end

  test "should reject token request for inactive user" do
    @user.update!(status: :locked)

    post api_v1_token_path, params: {
      passphrase: "#{@passphrase}:password"
    }, as: :json

    assert_response :forbidden
    json = JSON.parse(response.body)
    assert_equal "Account inactive", json["error"]
  end

  test "should require passphrase parameter" do
    post api_v1_token_path, params: {}, as: :json

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "Missing passphrase", json["error"]
  end

  test "should verify valid token" do
    # Generate a token first
    post api_v1_token_path, params: {
      passphrase: "#{@passphrase}:password"
    }, as: :json

    token = JSON.parse(response.body)["token"]

    # Now verify it
    get api_v1_verify_path, headers: {
      "Authorization" => "Bearer #{token}"
    }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json["valid"]
    assert json["expires_at"].present?
    assert json["subscription_expires"].present?
  end

  test "should reject invalid token on verify" do
    get api_v1_verify_path, headers: {
      "Authorization" => "Bearer invalid_token"
    }, as: :json

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal false, json["valid"]
  end

  test "should reject verify without token" do
    get api_v1_verify_path, as: :json

    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_equal "Missing token", json["error"]
  end
end
