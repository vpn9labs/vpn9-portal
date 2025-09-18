require "test_helper"

class RefreshTokenServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @user.subscriptions.destroy_all
    @subscription = @user.subscriptions.create!(
      plan: plans(:monthly),
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )
  end

  test "issue_for returns token and persists digest" do
    result = RefreshTokenService.issue_for(@user)

    assert_not_nil result
    assert result[:token].present?
    assert_equal ApiRefreshToken.digest(result[:token]), result[:record].token_hash
    assert_equal @user, result[:record].user
  end

  test "exchange rotates refresh token and increments usage" do
    original = RefreshTokenService.issue_for(@user)

    exchanged = RefreshTokenService.exchange(original[:token])

    assert_not_nil exchanged
    assert_equal @user, exchanged[:user]
    assert_not_equal original[:token], exchanged[:refresh_token]

    record = @user.api_refresh_tokens.first
    assert_equal ApiRefreshToken.digest(exchanged[:refresh_token]), record.token_hash
    assert_equal 1, record.usage_count
    assert record.last_used_at.present?
  end

  test "exchange returns nil for expired token" do
    issued = RefreshTokenService.issue_for(@user)
    issued[:record].update!(expires_at: 1.minute.ago)

    assert_nil RefreshTokenService.exchange(issued[:token])
  end

  test "issuing tokens enforces per user limit" do
    limit = RefreshTokenService::MAX_ACTIVE_TOKENS_PER_USER

    (limit + 2).times do
      RefreshTokenService.issue_for(@user)
      travel 1.second
    end

    assert_equal limit, @user.api_refresh_tokens.count
  ensure
    travel_back
  end

  test "revoke_for_user! removes all tokens" do
    RefreshTokenService.issue_for(@user)
    RefreshTokenService.revoke_for_user!(@user)

    assert_equal 0, @user.api_refresh_tokens.count
  end

  test "exchange returns nil when user inactive" do
    issued = RefreshTokenService.issue_for(@user)
    @user.update!(status: :locked)

    assert_nil RefreshTokenService.exchange(issued[:token])
    assert_equal 0, @user.api_refresh_tokens.count
  end

  test "exchange returns nil when subscription missing" do
    issued = RefreshTokenService.issue_for(@user)
    @subscription.update!(status: :cancelled)

    assert_nil RefreshTokenService.exchange(issued[:token])
    assert_equal 0, @user.api_refresh_tokens.count
  end
end
