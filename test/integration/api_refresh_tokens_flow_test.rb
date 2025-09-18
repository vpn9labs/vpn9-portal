require "test_helper"

class ApiRefreshTokensFlowTest < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.clear
    @user = User.create!(email_address: "flow@example.com", password: "password")
    @passphrase = @user.instance_variable_get(:@issued_passphrase)

    plan = plans(:monthly)
    @subscription = Subscription.create!(
      user: @user,
      plan: plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )
  end

  test "client can refresh token and rotated refresh becomes invalid" do
    post api_v1_token_path, params: { passphrase: "#{@passphrase}:password" }, as: :json
    assert_response :success

    initial = JSON.parse(response.body)
    refresh_token = initial["refresh_token"]

    post api_v1_refresh_path, params: { refresh_token: refresh_token }, as: :json
    assert_response :success
    refreshed = JSON.parse(response.body)

    assert_not_equal initial["token"], refreshed["token"], "Access token should change"
    assert_not_equal refresh_token, refreshed["refresh_token"], "Refresh token should rotate"

    post api_v1_refresh_path, params: { refresh_token: refresh_token }, as: :json
    assert_response :unauthorized
  end

  test "refresh token revoked when subscription becomes inactive" do
    post api_v1_token_path, params: { passphrase: "#{@passphrase}:password" }, as: :json
    refresh_token = JSON.parse(response.body)["refresh_token"]

    @subscription.update!(status: :cancelled)
    @user.reload

    assert_equal 0, @user.api_refresh_tokens.count, "Tokens should be revoked when subscription inactive"

    post api_v1_refresh_path, params: { refresh_token: refresh_token }, as: :json
    assert_response :unauthorized
  end
end
