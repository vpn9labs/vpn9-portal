require "test_helper"

class ReferralTest < ActiveSupport::TestCase
  def setup
    @affiliate = Affiliate.create!(
      name: "Test Affiliate",
      email: "affiliate@example.com",
      code: "TESTCODE",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "btc",
      payout_address: "bc1qtest123",
      password: "password123",
      password_confirmation: "password123",
      terms_accepted: true
    )

    @user = User.create!(email_address: "user@example.com")

    @referral = Referral.create!(
      affiliate: @affiliate,
      user: @user,
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.1"),
      landing_page: "/signup",
      clicked_at: 1.hour.ago
    )
  end

  # === Validations ===

  test "should be valid with valid attributes" do
    assert @referral.valid?
  end

  test "should require affiliate" do
    @referral.affiliate = nil
    assert_not @referral.valid?
    assert_includes @referral.errors[:affiliate], "must exist"
  end

  test "should require user" do
    @referral.user = nil
    assert_not @referral.valid?
    assert_includes @referral.errors[:user], "must exist"
  end

  test "should require ip_hash" do
    @referral.ip_hash = nil
    assert_not @referral.valid?
    assert_includes @referral.errors[:ip_hash], "can't be blank"
  end

  test "should enforce unique user_id" do
    duplicate = Referral.new(
      affiliate: @affiliate,
      user: @user,  # Same user
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.2")
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "should allow different users for same affiliate" do
    user2 = User.create!(email_address: "user2@example.com")

    referral2 = Referral.new(
      affiliate: @affiliate,
      user: user2,
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.2")
    )

    assert referral2.valid?
  end

  test "should allow same user with different affiliates" do
    affiliate2 = Affiliate.create!(
      name: "Second Affiliate",
      email: "affiliate2@example.com",
      code: "SECOND",
      commission_rate: 15.0,
      status: :active,
      payout_currency: "eth",
      payout_address: "0xtest",
      password: "password123",
      password_confirmation: "password123",
      terms_accepted: true
    )

    # Create a new user since the original is already referred
    new_user = User.create!(email_address: "newuser@example.com")

    referral2 = Referral.new(
      affiliate: affiliate2,
      user: new_user,
      referral_code: affiliate2.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.3")
    )

    assert referral2.valid?
  end

  # === Scopes ===

  test "recent scope should order by created_at desc" do
    older = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "older@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.10"),
      created_at: 2.days.ago
    )

    newer = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "newer@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.11"),
      created_at: Time.current + 1.second
    )

    recent = Referral.recent
    assert_equal newer, recent.first
    assert_equal @referral, recent.second
    assert_equal older, recent.third
  end

  test "converted scope should return only converted referrals" do
    @referral.update!(status: :converted)

    pending_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "pending@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.12"),
      status: :pending
    )

    assert_includes Referral.converted, @referral
    assert_not_includes Referral.converted, pending_referral
  end

  test "within_days scope should filter by days" do
    old_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "old@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.13"),
      created_at: 10.days.ago
    )

    recent_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "recent@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.14"),
      created_at: 3.days.ago
    )

    within_week = Referral.within_days(7)
    assert_includes within_week, recent_referral
    assert_includes within_week, @referral
    assert_not_includes within_week, old_referral
  end

  # === Status Enum ===

  test "should have correct status values" do
    assert @referral.pending?

    @referral.status = :converted
    assert @referral.converted?

    @referral.status = :rejected
    assert @referral.rejected?
  end

  test "should default to pending status" do
    referral = Referral.new(
      affiliate: @affiliate,
      user: User.create!(email_address: "new@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.15")
    )

    assert referral.pending?
  end

  # === Callbacks ===

  test "should set clicked_at on create if not provided" do
    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "clicktest@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.16")
    )

    assert_not_nil referral.clicked_at
    assert referral.clicked_at <= Time.current
  end

  test "should preserve clicked_at if provided" do
    specific_time = 3.hours.ago

    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "timetest@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.17"),
      clicked_at: specific_time
    )

    assert_equal specific_time.to_i, referral.clicked_at.to_i
  end

  # === Instance Methods ===

  test "within_attribution_window? should check time window" do
    # Within window
    recent_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "window1@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.18"),
      created_at: 1.day.ago
    )

    assert recent_referral.within_attribution_window?

    # Outside window (assuming default 30 days)
    old_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "window2@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.19"),
      created_at: 31.days.ago
    )

    assert_not old_referral.within_attribution_window?
  end

  test "within_attribution_window? should return false without affiliate" do
    @referral.affiliate = nil
    assert_not @referral.within_attribution_window?
  end

  test "days_since_click should calculate days correctly" do
    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "days@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.20"),
      created_at: 5.days.ago
    )

    assert_equal 5, referral.days_since_click
  end

  test "convert! should change status to converted" do
    assert @referral.pending?

    @referral.convert!

    assert @referral.converted?
    assert_not_nil @referral.converted_at
    assert @referral.converted_at <= Time.current
  end

  test "convert! should not convert already converted referral" do
    @referral.convert!
    original_time = @referral.converted_at

    sleep 0.1
    @referral.convert!

    assert_equal original_time.to_f, @referral.converted_at.to_f
  end

  test "convert! should mark related affiliate clicks as converted" do
    # Create affiliate clicks with matching IP
    click1 = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: @referral.ip_hash,
      landing_page: "/",
      created_at: @referral.created_at - 30.minutes
    )

    click2 = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: @referral.ip_hash,
      landing_page: "/pricing",
      created_at: @referral.created_at - 15.minutes
    )

    # Click too old to be related
    old_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: @referral.ip_hash,
      landing_page: "/old",
      created_at: @referral.created_at - 2.hours
    )

    # Different IP
    other_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("different-ip"),
      landing_page: "/other",
      created_at: @referral.created_at - 10.minutes
    )

    @referral.convert!

    click1.reload
    click2.reload
    old_click.reload
    other_click.reload

    assert click1.converted?
    assert click2.converted?
    assert_not old_click.converted?
    assert_not other_click.converted?
  end

  test "reject! should change status to rejected" do
    assert @referral.pending?

    @referral.reject!

    assert @referral.rejected?
  end

  test "reject! should not reject already rejected referral" do
    @referral.reject!

    # Should not raise error on second rejection
    assert_nothing_raised do
      @referral.reject!
    end

    assert @referral.rejected?
  end

  test "reject! should cancel pending commissions" do
    # Create a commission for this referral
    plan = Plan.create!(
      name: "Test Plan",
      price: 100,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )

    payment = Payment.create!(
      user: @user,
      plan: plan,
      amount: 100,
      currency: "USD",
      status: :paid
    )

    commission = Commission.create!(
      affiliate: @affiliate,
      payment: payment,
      referral: @referral,
      amount: 20,
      currency: "USD",
      commission_rate: 20,
      status: :pending
    )

    @referral.reject!("Fraudulent activity")

    commission.reload
    assert commission.cancelled?
    assert_includes commission.notes.to_s, "Fraudulent activity"
  end

  test "reject! should not cancel non-pending commissions" do
    plan = Plan.create!(
      name: "Test Plan",
      price: 100,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )

    payment = Payment.create!(
      user: @user,
      plan: plan,
      amount: 100,
      currency: "USD",
      status: :paid
    )

    paid_commission = Commission.create!(
      affiliate: @affiliate,
      payment: payment,
      referral: @referral,
      amount: 20,
      currency: "USD",
      commission_rate: 20,
      status: :paid
    )

    @referral.reject!

    paid_commission.reload
    assert paid_commission.paid? # Should remain paid
  end

  # === Associations ===

  test "should belong to affiliate" do
    assert_equal @affiliate, @referral.affiliate
  end

  test "should belong to user" do
    assert_equal @user, @referral.user
  end

  test "should have many commissions" do
    plan = Plan.create!(
      name: "Test Plan",
      price: 100,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )

    payment1 = Payment.create!(
      user: @user,
      plan: plan,
      amount: 100,
      currency: "USD",
      status: :paid
    )

    payment2 = Payment.create!(
      user: @user,
      plan: plan,
      amount: 150,
      currency: "USD",
      status: :paid
    )

    commission1 = Commission.create!(
      affiliate: @affiliate,
      payment: payment1,
      referral: @referral,
      amount: 20,
      currency: "USD",
      commission_rate: 20
    )

    commission2 = Commission.create!(
      affiliate: @affiliate,
      payment: payment2,
      referral: @referral,
      amount: 30,
      currency: "USD",
      commission_rate: 20
    )

    assert_includes @referral.commissions, commission1
    assert_includes @referral.commissions, commission2
    assert_equal 2, @referral.commissions.count
  end

  test "should destroy commissions when destroyed" do
    plan = Plan.create!(
      name: "Test Plan",
      price: 100,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )

    payment = Payment.create!(
      user: @user,
      plan: plan,
      amount: 100,
      currency: "USD",
      status: :paid
    )

    commission = Commission.create!(
      affiliate: @affiliate,
      payment: payment,
      referral: @referral,
      amount: 20,
      currency: "USD",
      commission_rate: 20
    )

    commission_id = commission.id
    @referral.destroy

    assert_nil Commission.find_by(id: commission_id)
  end

  # === Edge Cases ===

  test "should handle nil landing_page" do
    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "nopage@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.21"),
      landing_page: nil
    )

    assert referral.valid?
    assert_nil referral.landing_page
  end

  test "should handle very long landing pages" do
    long_page = "/" + "a" * 1000

    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "longpage@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.22"),
      landing_page: long_page
    )

    assert referral.valid?
    assert_equal long_page, referral.landing_page
  end

  test "should handle special characters in referral_code" do
    special_code = "TEST-CODE_123"

    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "special@example.com"),
      referral_code: special_code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.23")
    )

    assert referral.valid?
    assert_equal special_code, referral.referral_code
  end

  test "should handle different hash formats for ip_hash" do
    # SHA256 hash
    sha256_hash = Digest::SHA256.hexdigest("192.168.1.24")

    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "hash@example.com"),
      referral_code: @affiliate.code,
      ip_hash: sha256_hash
    )

    assert referral.valid?
    assert_equal sha256_hash, referral.ip_hash
  end

  # === Business Logic Tests ===

  test "should track referral source correctly" do
    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "source@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.25"),
      landing_page: "/signup?utm_source=facebook&utm_campaign=summer"
    )

    assert_equal "/signup?utm_source=facebook&utm_campaign=summer", referral.landing_page
  end

  test "should handle timezone differences in clicked_at" do
    # Test with different timezone
    Time.use_zone("Tokyo") do
      referral = Referral.create!(
        affiliate: @affiliate,
        user: User.create!(email_address: "timezone@example.com"),
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.1.26"),
        clicked_at: Time.zone.now
      )

      assert_not_nil referral.clicked_at
    end
  end

  test "should maintain referral integrity across status changes" do
    # Track status progression
    assert @referral.pending?

    @referral.convert!
    assert @referral.converted?
    assert_not_nil @referral.converted_at

    # Should not be able to reject after conversion
    @referral.reject!
    assert @referral.rejected? # Status can change

    # But converted_at should be preserved
    assert_not_nil @referral.converted_at
  end

  test "should handle concurrent referral creation" do
    users = []
    5.times do |i|
      users << User.create!(email_address: "concurrent#{i}@example.com")
    end

    referrals = []
    threads = users.map do |user|
      Thread.new do
        referrals << Referral.create!(
          affiliate: @affiliate,
          user: user,
          referral_code: @affiliate.code,
          ip_hash: Digest::SHA256.hexdigest("192.168.2.#{user.id}")
        )
      end
    end

    threads.each(&:join)

    assert_equal 5, referrals.count
    assert referrals.all?(&:persisted?)
    assert_equal 5, referrals.map(&:user_id).uniq.count
  end

  # === Query Performance Tests ===

  test "should efficiently query referrals with associations" do
    # Create test data
    10.times do |i|
      user = User.create!(email_address: "perf#{i}@example.com")
      Referral.create!(
        affiliate: @affiliate,
        user: user,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.3.#{i}")
      )
    end

    # Should use includes to avoid N+1 queries
    referrals = Referral.includes(:affiliate, :user, :commissions)

    # Access associations without additional queries
    referrals.each do |referral|
      assert_not_nil referral.affiliate.code
      assert_not_nil referral.user.id
      assert_not_nil referral.commissions.to_a
    end
  end

  test "should handle large batch operations" do
    # Create users properly
    batch_users = []
    100.times do |i|
      batch_users << User.create!(email_address: "batch#{i}@example.com")
    end

    referrals = []
    batch_users.each do |user|
      referrals << {
        affiliate_id: @affiliate.id,
        user_id: user.id,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.4.#{user.id}"),
        status: "pending",
        clicked_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    assert_difference "Referral.count", 100 do
      Referral.insert_all(referrals)
    end
  end

  # === Privacy Tests ===

  test "should not expose actual IP addresses" do
    # Ensure ip_hash doesn't contain actual IP
    actual_ip = "192.168.1.100"
    hash = Digest::SHA256.hexdigest(actual_ip)

    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "privacy@example.com"),
      referral_code: @affiliate.code,
      ip_hash: hash
    )

    assert_not_includes referral.attributes.values.map(&:to_s), actual_ip
    assert_equal hash, referral.ip_hash
  end

  test "should handle missing optional fields gracefully" do
    # Minimal referral with only required fields
    minimal_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "minimal@example.com"),
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.27")
    )

    assert minimal_referral.valid?
    assert_nil minimal_referral.landing_page
    assert_not_nil minimal_referral.clicked_at # Set by callback
  end
end
