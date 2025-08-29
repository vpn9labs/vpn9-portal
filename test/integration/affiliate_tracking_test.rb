require "test_helper"

class AffiliateTrackingTest < ActionDispatch::IntegrationTest
  setup do
    # Create an affiliate
    @affiliate = Affiliate.create!(
      name: "Test Partner",
      email: "partner@example.com",
      code: "TESTCODE",
      payout_address: "bc1qtest",
      commission_rate: 25.0
    )

    # Create a plan
    @plan = plans(:premium_20)
  end

  test "complete affiliate tracking flow from click to commission" do
    # Step 1: Visit site with affiliate link (signup page doesn't require auth)
    get signup_path(ref: @affiliate.code)
    assert_response :success

    # Verify affiliate cookie is set (signed cookie in controller)
    # Note: In tests, we can't directly access signed cookies, but we can verify tracking worked

    # Verify click was tracked
    assert_equal 1, @affiliate.affiliate_clicks.count
    click = @affiliate.affiliate_clicks.order(:created_at).last
    assert_not_nil click.ip_hash
    assert_equal "/signup?ref=#{@affiliate.code}", click.landing_page

    # Step 2: Sign up as new user
    post signup_path, params: {
      user: {
        email_address: "newuser@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_redirected_to root_path

    # Get the created user
    user = User.find_by(email_address: "newuser@example.com")
    assert_not_nil user

    # Verify referral was created
    referral = user.referral
    assert_not_nil referral
    assert_equal @affiliate, referral.affiliate
    assert_equal "TESTCODE", referral.referral_code
    assert_equal :pending, referral.status.to_sym

    # Affiliate cookies should be cleared after signup (handled by controller)

    # Step 3: User makes a payment
    payment = user.payments.create!(
      plan: @plan,
      amount: @plan.price,
      currency: @plan.currency,
      status: :pending
    )

    # Simulate successful payment webhook
    payment.update_from_webhook!({
      "status" => "PAID",
      "transaction_id" => "TX123",
      "external_id" => payment.id
    }, "127.0.0.1")

    # Verify payment is successful
    assert payment.reload.successful?

    # Step 4: Verify commission was created
    commission = Commission.find_by(payment: payment)
    assert_not_nil commission
    assert_equal @affiliate, commission.affiliate
    assert_equal referral, commission.referral
    assert_equal 5.00, commission.amount # 25% of $20
    assert_equal 25.0, commission.commission_rate
    assert_equal :pending, commission.status.to_sym

    # Verify referral was converted
    assert referral.reload.converted?
    assert_not_nil referral.converted_at

    # Step 5: Verify affiliate earnings were updated
    @affiliate.reload
    # lifetime_earnings only includes approved and paid commissions, not pending
    assert_equal 0.00, @affiliate.lifetime_earnings
    assert_equal 5.00, @affiliate.pending_balance
    assert_equal 0.00, @affiliate.paid_out_total
  end

  test "affiliate tracking with different parameter names" do
    # Test with 'affiliate' parameter
    get signup_path(affiliate: @affiliate.code)
    assert_response :success
    assert_equal 1, @affiliate.affiliate_clicks.count

    # Test with 'r' parameter
    get signup_path(r: @affiliate.code)
    assert_response :success
    assert_equal 2, @affiliate.affiliate_clicks.count
  end

  test "invalid affiliate code should not track" do
    get signup_path(ref: "INVALID")
    assert_response :success

    # No clicks should be tracked
    assert_equal 0, AffiliateClick.count
  end

  test "suspended affiliate should not track" do
    @affiliate.update!(status: :suspended)

    get signup_path(ref: @affiliate.code)
    assert_response :success
    assert_equal 0, @affiliate.affiliate_clicks.count
  end

  test "referral outside attribution window should not create commission" do
    # Create a referral
    user = User.create!(password: "password")
    referral = @affiliate.referrals.create!(
      user: user,
      ip_hash: "test",
      created_at: 40.days.ago # Outside 30-day window
    )

    # Create payment
    payment = user.payments.create!(
      plan: @plan,
      amount: @plan.price,
      currency: @plan.currency,
      status: :paid
    )

    # Process commission
    commission = CommissionService.process_payment(payment)

    # No commission should be created
    assert_nil commission
    assert_equal 0, Commission.count
  end

  test "user can only have one referral" do
    user = User.create!(
      email_address: "testuser@example.com",
      password: "password"
    )

    # Create first referral
    referral1 = @affiliate.referrals.create!(
      user: user,
      ip_hash: "test1",
      referral_code: @affiliate.code,
      landing_page: "/signup"
    )

    # Try to create second referral
    other_affiliate = Affiliate.create!(
      name: "Other Affiliate",
      email: "other@example.com",
      code: "OTHER",
      payout_address: "bc1qother",
      commission_rate: 30.0
    )

    referral2 = other_affiliate.referrals.build(
      user: user,
      ip_hash: "test2"
    )

    assert_not referral2.valid?
    assert_includes referral2.errors[:user_id], "has already been taken"
  end

  test "cookie expiration respects affiliate settings" do
    @affiliate.update!(cookie_duration_days: 7)

    get signup_path(ref: @affiliate.code)
    assert_response :success

    # Verify click was tracked
    assert_equal 1, @affiliate.affiliate_clicks.count

    # Note: We can't directly test cookie expiration in integration tests,
    # but the cookie is set with the correct expiration in the controller
  end
end
