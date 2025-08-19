require "test_helper"

class Admin::CommissionsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = Admin.create!(email: "admin@example.com", password: "password123")
    @affiliate = Affiliate.create!(
      name: "Test Affiliate",
      email: "affiliate@example.com",
      code: "TESTCODE",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "btc",
      payout_address: "bc1qtest123"
    )

    @user = User.create!(email_address: "user@example.com")
    @plan = Plan.create!(name: "Basic", price: 100, currency: "USD", duration_days: 30, device_limit: 5)
    @payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 100,
      currency: "USD",
      status: :paid,
      crypto_currency: "btc"
    )

    @referral = Referral.create!(
      affiliate: @affiliate,
      user: @user,
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("test-ip"),
      converted_at: Time.current
    )

    @commission = Commission.create!(
      affiliate: @affiliate,
      payment: @payment,
      referral: @referral,
      amount: 20.0,
      currency: "USD",
      commission_rate: 20.0,
      status: :pending
    )
  end

  def admin_sign_in
    post admin_session_path, params: { email: @admin.email, password: "password123" }
  end

  test "should get commissions index" do
    admin_sign_in
    get admin_commissions_path
    assert_response :success
    assert_select "h1", "Commissions"
  end

  test "should filter commissions by status" do
    admin_sign_in

    # Create additional commission with different status
    payment2 = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 75,
      currency: "USD",
      status: :paid
    )
    Commission.create!(
      affiliate: @affiliate,
      payment: payment2,
      referral: @referral,
      amount: 15.0,
      currency: "USD",
      commission_rate: 15.0,
      status: :paid,
      paid_at: Time.current
    )

    get admin_commissions_path(status: "pending")
    assert_response :success
    assert_match "$20.0", response.body  # Should see the pending commission
    # The paid commission of $15 will show in totals but not in the table
    assert_select "tbody tr", 1  # Should only show 1 commission in the table
  end

  test "should show commission details" do
    admin_sign_in
    get admin_commission_path(@commission)
    assert_response :success
    assert_match @affiliate.name, response.body
    assert_match "$20", response.body
  end

  test "should approve pending commission" do
    admin_sign_in
    assert @commission.pending?

    post approve_admin_commission_path(@commission), params: { notes: "Approved by admin" }
    assert_redirected_to admin_commissions_path

    @commission.reload
    assert @commission.approved?
    assert_not_nil @commission.approved_at
  end

  test "should not approve non-pending commission" do
    admin_sign_in
    @commission.update!(status: :paid)

    post approve_admin_commission_path(@commission)
    assert_redirected_to admin_commissions_path
    assert_equal "Commission cannot be approved", flash[:alert]
  end

  test "should cancel commission" do
    admin_sign_in

    post cancel_admin_commission_path(@commission), params: { reason: "Fraudulent activity" }
    assert_redirected_to admin_commissions_path

    @commission.reload
    assert @commission.cancelled?
    assert_match "Fraudulent activity", @commission.notes
  end

  test "should bulk approve commissions" do
    admin_sign_in

    # Create additional pending commissions
    payment2 = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 150,
      currency: "USD",
      status: :paid
    )
    commission2 = Commission.create!(
      affiliate: @affiliate,
      payment: payment2,
      referral: @referral,
      amount: 30.0,
      currency: "USD",
      commission_rate: 30.0,
      status: :pending
    )

    post bulk_approve_admin_commissions_path, params: {
      commission_ids: [ @commission.id, commission2.id ]
    }

    assert_redirected_to admin_commissions_path
    assert_equal "2 commissions approved", flash[:notice]

    @commission.reload
    commission2.reload
    assert @commission.approved?
    assert commission2.approved?
  end

  test "should bulk cancel commissions" do
    admin_sign_in

    payment2 = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 125,
      currency: "USD",
      status: :paid
    )
    commission2 = Commission.create!(
      affiliate: @affiliate,
      payment: payment2,
      referral: @referral,
      amount: 25.0,
      currency: "USD",
      commission_rate: 25.0,
      status: :approved
    )

    post bulk_cancel_admin_commissions_path, params: {
      commission_ids: [ @commission.id, commission2.id ],
      reason: "Bulk cancellation"
    }

    assert_redirected_to admin_commissions_path

    @commission.reload
    commission2.reload
    assert @commission.cancelled?
    assert commission2.cancelled?
  end

  test "should not cancel paid commissions in bulk" do
    admin_sign_in

    @commission.update!(status: :paid)
    payment2 = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 125,
      currency: "USD",
      status: :paid
    )
    commission2 = Commission.create!(
      affiliate: @affiliate,
      payment: payment2,
      referral: @referral,
      amount: 25.0,
      currency: "USD",
      commission_rate: 25.0,
      status: :pending
    )

    post bulk_cancel_admin_commissions_path, params: {
      commission_ids: [ @commission.id, commission2.id ]
    }

    @commission.reload
    commission2.reload
    assert @commission.paid? # Should remain paid
    assert commission2.cancelled? # Should be cancelled
  end

  test "should calculate totals correctly" do
    admin_sign_in

    # Create commissions with different statuses
    payment2 = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 250,
      currency: "USD",
      status: :paid
    )
    Commission.create!(
      affiliate: @affiliate,
      payment: payment2,
      referral: @referral,
      amount: 50.0,
      currency: "USD",
      status: :approved
    )

    payment3 = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 375,
      currency: "USD",
      status: :paid
    )
    Commission.create!(
      affiliate: @affiliate,
      payment: payment3,
      referral: @referral,
      amount: 75.0,
      currency: "USD",
      status: :paid
    )

    get admin_commissions_path
    assert_response :success

    # Check that totals are displayed
    assert_match "$20", response.body # Pending
    assert_match "$50", response.body # Approved
    assert_match "$75", response.body # Paid
  end
end
