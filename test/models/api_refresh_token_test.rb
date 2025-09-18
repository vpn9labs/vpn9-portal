require "test_helper"

class ApiRefreshTokenTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @token = @user.api_refresh_tokens.create!(
      token_hash: ApiRefreshToken.digest("token"),
      expires_at: 1.day.from_now,
      last_used_at: Time.current
    )
  end

  test "requires token hash" do
    token = ApiRefreshToken.new(user: @user, expires_at: 1.day.from_now)

    assert_not token.valid?
    assert_includes token.errors[:token_hash], "can't be blank"
  end

  test "requires expires_at" do
    token = ApiRefreshToken.new(user: @user, token_hash: "abc")

    assert_not token.valid?
    assert_includes token.errors[:expires_at], "can't be blank"
  end

  test "expired? returns true when past expiration" do
    @token.update!(expires_at: 1.hour.ago)

    assert @token.expired?
  end

  test "expired? returns false when future expiration" do
    assert_not @token.expired?
  end

  test "digest generates sha256 hash" do
    digest = ApiRefreshToken.digest("value")
    assert_equal 64, digest.length
  end
end
