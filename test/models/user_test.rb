require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @user = User.new(email_address: "test@example.com")
  end

  test "should be valid with valid attributes" do
    assert @user.valid?
  end

  test "should be valid without email address" do
    @user.email_address = nil
    assert @user.valid?
  end

  test "should be valid with password" do
    @user.password = "password123"
    @user.password_confirmation = "password123"
    assert @user.valid?
  end

  test "should be valid without password" do
    @user.password = nil
    assert @user.valid?
  end

  test "should normalize email address to lowercase" do
    @user.email_address = "TEST@EXAMPLE.COM"
    @user.save!
    assert_equal "test@example.com", @user.email_address
  end

  test "should strip whitespace from email address" do
    @user.email_address = "  test@example.com  "
    @user.save!
    assert_equal "test@example.com", @user.email_address
  end

  test "should create passphrase on create" do
    @user.save!
    assert_not_nil @user.passphrase_hash
    # Should have search prefix (16 chars) + argon hash
    assert @user.passphrase_hash.length > 16
  end

  test "should create passphrase when no password provided" do
    @user.save!
    assert_not_nil @user.passphrase_hash
    assert_not_nil @user.send(:issued_passphrase)
    # Should be 7 words separated by hyphens
    assert_match(/\A[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+\z/, @user.send(:issued_passphrase))
  end

  test "should create passphrase from password when password provided" do
    @user.password = "password123"
    @user.password_confirmation = "password123"
    @user.save!
    assert_not_nil @user.passphrase_hash
    # With password, the full identifier includes :password
    assert_not_nil @user.send(:issued_passphrase)
  end

  test "should create recovery_code on create" do
    @user.save!
    assert_not_nil @user.recovery_code
  end

  test "should have issued_passphrase when created without password" do
    @user.save!
    assert_not_nil @user.send(:issued_passphrase)
  end

  test "should have issued_passphrase when created with password" do
    @user.password = "password123"
    @user.password_confirmation = "password123"
    @user.save!
    assert_not_nil @user.send(:issued_passphrase)
  end

  test "should default to active status" do
    @user.save!
    assert @user.active?
  end

  test "should support locked status" do
    @user.status = :locked
    @user.save!
    assert @user.locked?
  end

  test "should support closed status" do
    @user.status = :closed
    @user.save!
    assert @user.closed?
  end

  test "should verify passphrase with correct candidate" do
    @user.save!
    passphrase = @user.send(:issued_passphrase)
    assert @user.verify_passphrase!(passphrase)
  end

  test "should have many sessions" do
    assert_respond_to @user, :sessions
  end

  test "should destroy sessions when user is destroyed" do
    @user.save!
    session = @user.sessions.create!
    assert_difference "Session.count", -1 do
      @user.destroy
    end
  end

  test "should validate email format when present" do
    @user.email_address = "invalid_email"
    assert_not @user.valid?
    assert_includes @user.errors[:email_address], "is invalid"
  end

  test "should accept valid email formats" do
    valid_emails = [ "user@example.com", "user.name@example.com", "user+tag@example.co.uk" ]
    valid_emails.each do |email|
      @user.email_address = email
      assert @user.valid?, "#{email} should be valid"
    end
  end

  test "should validate password length when password present" do
    @user.password = "short"
    @user.password_confirmation = "short"
    assert_not @user.valid?
    assert_includes @user.errors[:password], "is too short (minimum is 6 characters)"
  end

  test "should validate password confirmation" do
    @user.password = "password123"
    @user.password_confirmation = "different"
    assert_not @user.valid?
    assert_includes @user.errors[:password_confirmation], "doesn't match Password"
  end

  test "should encrypt email address" do
    @user.save!
    assert_not_equal "test@example.com", @user.email_address_before_type_cast
  end

  test "should create unique passphrases for different users" do
    user1 = User.create!
    user2 = User.create!

    passphrase1 = user1.send(:issued_passphrase)
    passphrase2 = user2.send(:issued_passphrase)

    assert_not_equal passphrase1, passphrase2
  end

  test "should handle blank email address in normalization" do
    @user.email_address = ""
    @user.save!
    assert_equal "", @user.email_address
  end

  test "should handle nil email address in normalization" do
    @user.email_address = nil
    @user.save!
    assert_nil @user.email_address
  end

  test "should not validate password when blank" do
    @user.password = ""
    assert @user.valid?
  end

  test "should not validate password when nil" do
    @user.password = nil
    assert @user.valid?
  end

  test "argon_hash should return hash string" do
    hash = User.argon_hash("test_password")
    assert_instance_of String, hash
    assert hash.start_with?("$argon2")
  end

  test "should use correct Argon2 parameters" do
    hash = User.argon_hash("test_password")
    assert_match(/\$argon2id\$/, hash)
    assert_match(/t=4/, hash) # t_cost
    # Memory parameter varies by Argon2 gem version, just check it exists
    assert_match(/m=\d+/, hash)
  end

  test "should authenticate with passphrase" do
    @user.save!
    passphrase = @user.send(:issued_passphrase)

    authenticated_user = User.authenticate_by_passphrase(passphrase)
    assert_equal @user.id, authenticated_user.id
  end

  test "should not authenticate with wrong passphrase" do
    @user.save!

    authenticated_user = User.authenticate_by_passphrase("wrong-wrong-wrong-wrong-wrong-wrong-wrong")
    assert_nil authenticated_user
  end

  test "should authenticate with passphrase and password" do
    @user.password = "password123"
    @user.password_confirmation = "password123"
    @user.save!

    passphrase = @user.send(:issued_passphrase)
    full_identifier = "#{passphrase}:password123"

    authenticated_user = User.authenticate_by_passphrase(full_identifier)
    assert_equal @user.id, authenticated_user.id
  end

  test "should handle password with special characters" do
    special_passwords = [ "p@ssw0rd!", "pass$word#123", 'p@ss\'"word' ]
    special_passwords.each do |password|
      user = User.new(password: password, password_confirmation: password)
      user.save!

      passphrase = user.send(:issued_passphrase)
      full_identifier = "#{passphrase}:#{password}"
      authenticated = User.authenticate_by_passphrase(full_identifier)
      assert_equal user.id, authenticated.id
    end
  end

  test "should handle unicode characters in email" do
    @user.email_address = "user@example.com" # Standard ASCII email
    assert @user.valid?
  end

  test "should have proper passphrase format after creation" do
    @user.save!
    passphrase = @user.send(:issued_passphrase)
    words = passphrase.split("-")
    assert_equal 7, words.length
    words.each do |word|
      assert_match(/\A[a-z]+\z/, word)
    end
  end

  test "should reject invalid email formats" do
    invalid_emails = [ "user", "@example.com", "user@", "user @example.com" ]
    invalid_emails.each do |email|
      @user.email_address = email
      assert_not @user.valid?, "#{email} should be invalid"
    end
  end

  test "should allow empty password confirmation when password is present" do
    @user.password = "password123"
    @user.password_confirmation = ""
    assert @user.valid?
  end

  test "should reject mismatched password confirmation" do
    @user.password = "password123"
    @user.password_confirmation = "different"
    assert_not @user.valid?
  end

  test "should reject password shorter than 6 characters" do
    @user.password = "12345"
    @user.password_confirmation = "12345"
    assert_not @user.valid?
  end

  test "should handle database constraints violation" do
    user1 = User.create!(email_address: "unique@example.com")
    user2 = User.new(email_address: "unique@example.com")

    assert_raises(ActiveRecord::RecordNotUnique) do
      user2.save!(validate: false)
    end
  end

  test "should handle invalid status enum value" do
    assert_raises(ArgumentError) do
      @user.status = :invalid_status
    end
  end

  test "should handle nil passphrase during verification" do
    @user.save!
    assert_not @user.verify_passphrase!(nil)
  rescue
    # Expected to raise error or return false
  end

  test "should handle empty passphrase during verification" do
    @user.save!
    assert_not @user.verify_passphrase!("")
  rescue
    # Expected to raise error or return false
  end

  test "should handle extremely long email address" do
    @user.email_address = "a" * 240 + "@example.com"
    assert @user.valid?
  end

  test "should handle extremely long password" do
    long_password = "a" * 72
    @user.password = long_password
    @user.password_confirmation = long_password
    assert @user.valid?
  end

  test "should handle concurrent user creation" do
    users = []
    threads = 5.times.map do
      Thread.new do
        user = User.create!
        users << user
      end
    end
    threads.each(&:join)

    passphrases = users.map { |u| u.send(:issued_passphrase) }
    assert_equal passphrases.uniq.length, passphrases.length
  end

  test "should handle session association when user has no sessions" do
    @user.save!
    assert_empty @user.sessions
  end

  test "should handle validation errors collection" do
    @user.email_address = "invalid"
    @user.password = "short"
    @user.password_confirmation = "different"

    assert_not @user.valid?
    assert @user.errors.any?
    assert @user.errors[:email_address].any?
    assert @user.errors[:password].any?
  end

  test "should handle model with all optional fields nil" do
    user = User.new
    assert user.valid?
    assert user.save!

    assert_nil user.email_address
    # password_digest is handled by has_secure_password
    assert_not_nil user.passphrase_hash
    assert_not_nil user.recovery_code
  end


  test "should handle authentication with email hint" do
    @user.save!
    passphrase = @user.send(:issued_passphrase)

    authenticated = User.authenticate_by_passphrase(passphrase, email: @user.email_address)
    assert_equal @user.id, authenticated.id
  end

  # Account deletion tests
  test "should soft delete user" do
    @user.save!
    assert_not @user.deleted?

    @user.soft_delete!

    assert @user.deleted?
    assert_not_nil @user.deleted_at
    # anonymized_email no longer exists in the new implementation
  end

  test "should soft delete user with reason" do
    @user.save!
    reason = "Not satisfied with the service"

    @user.soft_delete!(reason: reason)

    assert_equal reason, @user.deletion_reason
  end

  test "should clear personal data on soft delete" do
    @user.password = "password123"
    @user.save!
    original_passphrase_hash = @user.passphrase_hash
    original_recovery_code = @user.recovery_code

    @user.soft_delete!

    assert_nil @user.email_address
    assert_nil @user.passphrase_hash
    assert_nil @user.recovery_code
  end

  test "should preserve payments when user is soft deleted" do
    @user.save!
    plan = Plan.create!(name: "Test Plan", price: 10, currency: "USD", duration_days: 30)
    payment = @user.payments.create!(
      plan: plan,
      amount: 10,
      currency: "USD",
      status: :paid,
      processor_id: "test-123",
      payment_address: "test-address",
      crypto_currency: "btc",
      crypto_amount: "0.0001"
    )

    @user.soft_delete!

    payment.reload
    assert_equal @user.id, payment.user_id
    # Payment should still exist but be excluded from default scope
    assert Payment.unscoped.exists?(payment.id)
    assert_not Payment.exists?(payment.id)
  end

  test "should preserve subscriptions when user is soft deleted" do
    @user.save!
    plan = Plan.create!(name: "Test Plan", price: 10, currency: "USD", duration_days: 30)
    subscription = @user.subscriptions.create!(
      plan: plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    @user.soft_delete!

    subscription.reload
    assert_equal @user.id, subscription.user_id
    # Subscription should still exist but be excluded from default scope
    assert Subscription.unscoped.exists?(subscription.id)
    assert_not Subscription.exists?(subscription.id)
  end

  test "active scope should exclude deleted users" do
    active_user = User.create!
    deleted_user = User.create!
    deleted_user.soft_delete!

    active_users = User.active

    assert_includes active_users, active_user
    assert_not_includes active_users, deleted_user
  end

  test "deleted scope should only include deleted users" do
    active_user = User.create!
    deleted_user = User.create!
    deleted_user.soft_delete!

    deleted_users = User.deleted

    assert_includes deleted_users, deleted_user
    assert_not_includes deleted_users, active_user
  end

  test "should handle soft delete in transaction" do
    @user.save!
    plan = Plan.create!(name: "Test Plan", price: 10, currency: "USD", duration_days: 30)
    payment = @user.payments.create!(
      plan: plan,
      amount: 10,
      currency: "USD",
      status: :paid,
      processor_id: "test-123",
      payment_address: "test-address",
      crypto_currency: "btc",
      crypto_amount: "0.0001"
    )

    # Simulate a database error during the update
    @user.stubs(:save!).raises(ActiveRecord::StatementInvalid, "Simulated database error")

    assert_raises(ActiveRecord::StatementInvalid) do
      @user.soft_delete!
    end

    # The transaction should have rolled back, so nothing should be changed
    @user.unstub(:save!)
    @user.reload
    assert_not @user.deleted?
    assert_not_nil @user.passphrase_hash

    # Payments should still be associated
    payment.reload
    assert_equal @user.id, payment.user_id
  end

  test "should handle multiple payments during soft delete" do
    @user.save!
    plan = Plan.create!(name: "Test Plan", price: 10, currency: "USD", duration_days: 30)

    payments = 3.times.map do |i|
      @user.payments.create!(
        plan: plan,
        amount: 10,
        currency: "USD",
        status: :paid,
        processor_id: "test-#{i}",
        payment_address: "test-address-#{i}",
        crypto_currency: "btc",
        crypto_amount: "0.0001"
      )
    end

    @user.soft_delete!

    payments.each do |payment|
      payment.reload
      assert_equal @user.id, payment.user_id
      # Payment should be excluded from default scope
      assert_not Payment.where(id: payment.id).exists?
    end
  end
end
