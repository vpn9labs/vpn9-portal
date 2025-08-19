require "test_helper"

class AffiliateTest < ActiveSupport::TestCase
  setup do
    @affiliate = Affiliate.new(
      name: "Test Affiliate",
      email: "affiliate@example.com",
      payout_address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
      payout_currency: "btc",
      commission_rate: 20.0
    )
  end

  test "should be valid with valid attributes" do
    assert @affiliate.valid?
  end

  test "should require payout_address" do
    @affiliate.payout_address = nil
    assert_not @affiliate.valid?
    assert_includes @affiliate.errors[:payout_address], "can't be blank"
  end

  test "should validate commission_rate range" do
    @affiliate.commission_rate = -1
    assert_not @affiliate.valid?

    @affiliate.commission_rate = 101
    assert_not @affiliate.valid?

    @affiliate.commission_rate = 50
    assert @affiliate.valid?
  end

  test "should generate unique code on create" do
    @affiliate.save!
    assert_not_nil @affiliate.code
    assert_match /^[A-Z0-9]{8}$/, @affiliate.code
  end

  test "should ensure code uniqueness" do
    @affiliate.save!

    duplicate = Affiliate.new(
      code: @affiliate.code,
      payout_address: "different_address",
      commission_rate: 15.0
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:code], "has already been taken"
  end

  test "should normalize code to uppercase" do
    @affiliate.code = "test123"
    @affiliate.save!
    assert_equal "TEST123", @affiliate.reload.code
  end

  test "should calculate conversion rate" do
    @affiliate.save!

    # Create some clicks
    3.times do
      @affiliate.affiliate_clicks.create!(
        ip_hash: SecureRandom.hex,
        user_agent_hash: SecureRandom.hex
      )
    end

    # Create a converted referral
    user = User.create!(password: "password")
    referral = @affiliate.referrals.create!(
      user: user,
      ip_hash: SecureRandom.hex,
      status: :converted
    )

    assert_equal 33.33, @affiliate.conversion_rate
  end

  test "should generate referral link" do
    @affiliate.code = "TESTCODE"
    assert_equal "https://vpn9.com?ref=TESTCODE", @affiliate.referral_link
    assert_equal "https://example.com?ref=TESTCODE", @affiliate.referral_link("https://example.com")
  end

  test "should track pending and approved commissions" do
    @affiliate.save!

    # Create user and payment
    user = User.create!(password: "password")
    plan = Plan.create!(
      name: "Test Plan",
      price: 10.00,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )
    payment = user.payments.create!(
      plan: plan,
      amount: 10.00,
      currency: "USD",
      status: :paid
    )
    referral = @affiliate.referrals.create!(
      user: user,
      ip_hash: SecureRandom.hex
    )

    # Create pending commission
    pending_commission = @affiliate.commissions.create!(
      payment: payment,
      referral: referral,
      amount: 2.00,
      currency: "USD",
      commission_rate: 20.0,
      status: :pending
    )

    assert_equal 2.00, @affiliate.total_pending_commission
    assert_equal 0.00, @affiliate.total_approved_commission

    # Approve commission
    pending_commission.approve!

    assert_equal 0.00, @affiliate.total_pending_commission # Now approved, not pending
    assert_equal 2.00, @affiliate.total_approved_commission
  end

  test "should check eligibility for payout" do
    @affiliate.save!
    assert_not @affiliate.eligible_for_payout?(50.0)

    # Add approved commission
    user = User.create!(password: "password")
    plan = Plan.create!(
      name: "Test Plan",
      price: 100.00,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )
    payment = user.payments.create!(
      plan: plan,
      amount: 100.00,
      currency: "USD",
      status: :paid
    )
    referral = @affiliate.referrals.create!(
      user: user,
      ip_hash: SecureRandom.hex
    )

    commission = @affiliate.commissions.create!(
      payment: payment,
      referral: referral,
      amount: 60.00,
      currency: "USD",
      commission_rate: 20.0,
      status: :approved
    )

    assert @affiliate.eligible_for_payout?(50.0)
    assert_not @affiliate.eligible_for_payout?(100.0)
  end
end
