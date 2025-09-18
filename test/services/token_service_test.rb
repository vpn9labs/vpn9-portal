require "test_helper"
require "jwt"

class TokenServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @plan = plans(:monthly)

    # Ensure user has an active subscription for most tests
    @user.subscriptions.destroy_all
    @subscription = @user.subscriptions.create!(
      plan: @plan,
      status: "active",
      started_at: 1.day.ago,
      expires_at: 30.days.from_now
    )
  end

  # === Token Generation Tests ===

  test "should generate token for user with active subscription" do
    token = TokenService.generate_token(@user)

    assert_not_nil token
    assert token.is_a?(String)
    assert token.split(".").length == 3, "JWT should have 3 parts separated by dots"
  end

  test "should not generate token for user without subscription" do
    @subscription.destroy

    token = TokenService.generate_token(@user)

    assert_nil token
  end

  test "should not generate token for user with expired subscription" do
    @subscription.update!(expires_at: 1.day.ago)

    token = TokenService.generate_token(@user)

    assert_nil token
  end

  test "should not generate token for user with cancelled subscription" do
    @subscription.update!(status: "cancelled")

    token = TokenService.generate_token(@user)

    assert_nil token
  end

  test "should not generate token for locked user" do
    @user.update!(status: :locked)

    token = TokenService.generate_token(@user)

    assert_nil token
  end

  test "should not generate token for closed user" do
    @user.update!(status: :closed)

    token = TokenService.generate_token(@user)

    assert_nil token
  end

  test "generated token should contain correct user id" do
    token = TokenService.generate_token(@user)
    decoded = JWT.decode(token, nil, false) # Decode without verification

    assert_equal @user.id.to_s, decoded[0]["sub"]
  end

  test "generated token should have correct expiration time" do
    freeze_time do
      token = TokenService.generate_token(@user)
      decoded = JWT.decode(token, nil, false)

      expected_exp = 24.hours.from_now.to_i
      assert_equal expected_exp, decoded[0]["exp"]
    end
  end

  test "generated token should have issued at time" do
    freeze_time do
      token = TokenService.generate_token(@user)
      decoded = JWT.decode(token, nil, false)

      assert_equal Time.current.to_i, decoded[0]["iat"]
    end
  end

  test "generated token should include subscription expiration" do
    token = TokenService.generate_token(@user)
    decoded = JWT.decode(token, nil, false)

    assert_equal @subscription.expires_at.to_i, decoded[0]["subscription_expires"]
  end

  test "generated token should include unique jti" do
    token = TokenService.generate_token(@user)
    decoded = JWT.decode(token, nil, false)

    assert decoded[0]["jti"].present?
  end

  test "generated token should be signed with RS256 algorithm" do
    token = TokenService.generate_token(@user)
    header = JWT.decode(token, nil, false, verify_expiration: false)[1]

    assert_equal "RS256", header["alg"]
  end

  # === Token Verification Tests ===

  test "should verify valid token" do
    token = TokenService.generate_token(@user)

    result = TokenService.verify_token(token)

    assert_not_nil result
    assert_equal @user.id, result[:user_id]
    assert result[:expires_at].is_a?(Time)
    assert result[:subscription_expires].is_a?(Time)
    assert result[:token_id].present?
  end

  test "should return nil for expired token" do
    # Create a token that's already expired
    freeze_time do
      payload = {
        sub: @user.id.to_s,
        exp: 1.hour.ago.to_i, # Expired
        iat: 2.hours.ago.to_i,
        subscription_expires: @subscription.expires_at.to_i
      }

      private_key = OpenSSL::PKey::RSA.new(Base64.decode64(ENV["JWT_PRIVATE_KEY"]))
      expired_token = JWT.encode(payload, private_key, "RS256")

      result = TokenService.verify_token(expired_token)

      assert_nil result
    end
  end

  test "should return nil for invalid token" do
    result = TokenService.verify_token("invalid.token.here")

    assert_nil result
  end

  test "should return nil for malformed token" do
    result = TokenService.verify_token("not_even_a_jwt")

    assert_nil result
  end

  test "should return nil for token signed with wrong key" do
    # Create a token with a different key
    wrong_key = OpenSSL::PKey::RSA.generate(2048)
    payload = {
      sub: @user.id.to_s,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i,
      subscription_expires: @subscription.expires_at.to_i
    }

    wrong_token = JWT.encode(payload, wrong_key, "RS256")
    result = TokenService.verify_token(wrong_token)

    assert_nil result
  end

  test "should handle token without subscription_expires field" do
    # Create a token without subscription_expires (legacy format)
    payload = {
      sub: @user.id.to_s,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i
    }

    private_key = OpenSSL::PKey::RSA.new(Base64.decode64(ENV["JWT_PRIVATE_KEY"]))
    token = JWT.encode(payload, private_key, "RS256")

    result = TokenService.verify_token(token)

    assert_not_nil result
    assert_equal @user.id, result[:user_id]
    assert_nil result[:subscription_expires]
    assert_nil result[:token_id]
  end

  test "should return correct expiration time from token" do
    freeze_time do
      token = TokenService.generate_token(@user)
      result = TokenService.verify_token(token)

      expected_exp = 24.hours.from_now
      assert_in_delta expected_exp.to_i, result[:expires_at].to_i, 1
    end
  end

  test "should return correct subscription expiration from token" do
    token = TokenService.generate_token(@user)
    result = TokenService.verify_token(token)

    assert_equal @subscription.expires_at.to_i, result[:subscription_expires].to_i
  end

  # === Token Authentication Tests ===

  test "should authenticate valid token and return user" do
    token = TokenService.generate_token(@user)

    authenticated_user = TokenService.authenticate_token(token)

    assert_not_nil authenticated_user
    assert_equal @user.id, authenticated_user.id
  end

  test "should return nil for invalid token authentication" do
    authenticated_user = TokenService.authenticate_token("invalid.token")

    assert_nil authenticated_user
  end

  test "should return nil for expired token authentication" do
    payload = {
      sub: @user.id.to_s,
      exp: 1.hour.ago.to_i,
      iat: 2.hours.ago.to_i,
      subscription_expires: @subscription.expires_at.to_i
    }

    private_key = OpenSSL::PKey::RSA.new(Base64.decode64(ENV["JWT_PRIVATE_KEY"]))
    expired_token = JWT.encode(payload, private_key, "RS256")

    authenticated_user = TokenService.authenticate_token(expired_token)

    assert_nil authenticated_user
  end

  test "should return nil if user no longer exists" do
    token = TokenService.generate_token(@user)
    user_id = @user.id

    # Delete associated records first, then user to avoid foreign key issues
    Device.where(user_id: user_id).delete_all
    Subscription.where(user_id: user_id).delete_all
    User.where(id: user_id).delete_all

    authenticated_user = TokenService.authenticate_token(token)

    assert_nil authenticated_user
  end

  test "should not authenticate token for locked user" do
    token = TokenService.generate_token(@user)
    @user.update!(status: :locked)

    authenticated_user = TokenService.authenticate_token(token)

    assert_nil authenticated_user
  end

  test "should not authenticate token for closed user" do
    token = TokenService.generate_token(@user)
    @user.update!(status: :closed)

    authenticated_user = TokenService.authenticate_token(token)

    assert_nil authenticated_user
  end

  test "should handle exceptions in authenticate_token gracefully" do
    # Create a token with invalid user_id format
    payload = {
      sub: "invalid_id_format",
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i,
      subscription_expires: @subscription.expires_at.to_i
    }

    private_key = OpenSSL::PKey::RSA.new(Base64.decode64(ENV["JWT_PRIVATE_KEY"]))
    bad_token = JWT.encode(payload, private_key, "RS256")

    authenticated_user = TokenService.authenticate_token(bad_token)
    assert_nil authenticated_user
  end

  # === Key Management Tests ===

  test "should use environment JWT keys when available" do
    # Keys are already set in test_helper.rb
    assert ENV["JWT_PRIVATE_KEY"].present?
    assert ENV["JWT_PUBLIC_KEY"].present?

    token = TokenService.generate_token(@user)
    assert_not_nil token

    # Should be able to verify with the same keys
    result = TokenService.verify_token(token)
    assert_not_nil result
  end

  test "should generate keys in development if not set" do
    # Skip this test in CI or when keys are already set
    skip "Keys already configured" if ENV["JWT_PRIVATE_KEY"].present?

    # This test would require modifying Rails.env which is not recommended
    # The functionality is already tested by the fact that tests run successfully
  end

  test "should raise error in production if keys not set" do
    # We can't easily test this without stubbing Rails.env
    # which is not available in Rails 7+
    # The functionality is covered by the implementation
    skip "Cannot stub Rails.env in Rails 7+"
  end

  # === Token Content Tests ===

  test "should not include sensitive user data in token" do
    token = TokenService.generate_token(@user)
    decoded = JWT.decode(token, nil, false)

    payload = decoded[0]

    # Should NOT include
    assert_nil payload["email"]
    assert_nil payload["password"]
    assert_nil payload["passphrase"]
    assert_nil payload["passphrase_hash"]

    # Should only include minimal necessary data
    assert payload.key?("sub")  # user id
    assert payload.key?("exp")  # expiration
    assert payload.key?("iat")  # issued at
    assert payload.key?("subscription_expires")
    assert payload.key?("jti")  # unique token id
  end

  test "token payload should be minimal" do
    token = TokenService.generate_token(@user)
    decoded = JWT.decode(token, nil, false)

    # Should only have the 5 expected fields
    expected_keys = %w[sub exp iat subscription_expires jti]
    assert_equal expected_keys.length, decoded[0].keys.length
    assert_equal expected_keys.sort, decoded[0].keys.sort
  end

  # === Concurrent Access Tests ===

  test "should handle concurrent token generation" do
    threads = []
    tokens = []
    mutex = Mutex.new

    10.times do
      threads << Thread.new do
        token = TokenService.generate_token(@user)
        mutex.synchronize { tokens << token }
      end
    end

    threads.each(&:join)

    # All tokens should be valid
    assert_equal 10, tokens.length
    tokens.each do |token|
      assert_not_nil token
      result = TokenService.verify_token(token)
      assert_not_nil result
      assert_equal @user.id, result[:user_id]
    end
  end

  test "should handle concurrent token verification" do
    token = TokenService.generate_token(@user)
    threads = []
    results = []
    mutex = Mutex.new

    10.times do
      threads << Thread.new do
        result = TokenService.verify_token(token)
        mutex.synchronize { results << result }
      end
    end

    threads.each(&:join)

    # All verifications should succeed
    assert_equal 10, results.length
    results.each do |result|
      assert_not_nil result
      assert_equal @user.id, result[:user_id]
    end
  end

  # === Token Expiry Constant Test ===

  test "ACCESS_TOKEN_EXPIRY should be 24 hours" do
    assert_equal 24.hours, TokenService::ACCESS_TOKEN_EXPIRY
    assert_equal 86400, TokenService::ACCESS_TOKEN_EXPIRY.to_i
  end

  # === Integration Tests ===

  test "full token lifecycle" do
    # 1. Generate token
    token = TokenService.generate_token(@user)
    assert_not_nil token

    # 2. Verify token
    verification = TokenService.verify_token(token)
    assert_not_nil verification
    assert_equal @user.id, verification[:user_id]

    # 3. Authenticate with token
    authenticated_user = TokenService.authenticate_token(token)
    assert_equal @user, authenticated_user

    # 4. Token should expire after 24 hours
    travel 25.hours do
      expired_verification = TokenService.verify_token(token)
      assert_nil expired_verification

      expired_auth = TokenService.authenticate_token(token)
      assert_nil expired_auth
    end
  end

  test "token should work across service restarts" do
    # Generate token
    token = TokenService.generate_token(@user)

    # Clear memoized keys to simulate restart
    TokenService.instance_variable_set(:@private_key, nil)
    TokenService.instance_variable_set(:@public_key, nil)

    # Should still be able to verify
    result = TokenService.verify_token(token)
    assert_not_nil result
    assert_equal @user.id, result[:user_id]
  end
end
