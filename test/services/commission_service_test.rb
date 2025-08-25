require "test_helper"

class CommissionServiceTest < ActiveSupport::TestCase
  def setup
    Rails.application.config.auto_approve_commission_threshold = 50.0
    Rails.application.config.minimum_payout_amount = 100.0

    @affiliate = Affiliate.create!(
      code: "AFFTEST",
      email: "aff@example.com",
      commission_rate: 20.0,
      status: :active,
      attribution_window_days: 30,
      payout_address: "bc1qtestaddress",
      payout_currency: "btc"
    )

    @user = users(:one)
    @plan = plans(:monthly)

    # Pending referral within attribution window
    @referral = Referral.create!(
      affiliate: @affiliate,
      user: @user,
      ip_hash: "iphash-1",
      created_at: 1.day.ago
    )

    @payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 100.0,
      currency: "USD",
      status: :paid
    )
  end

  test "process_payment creates commission and converts referral on first successful payment" do
    assert_difference "Commission.count", 1 do
      commission = CommissionService.process_payment(@payment)
      assert commission.present?
      assert_equal @affiliate, commission.affiliate
      assert_equal @payment, commission.payment
      assert_equal @referral, commission.referral
      assert_equal 20.0, commission.amount
      assert_equal "USD", commission.currency
      assert_equal 20.0, commission.commission_rate
    end

    assert @referral.reload.converted?, "Referral should be marked converted on first successful payment"
  end

  test "process_payment auto-approves small commission" do
    # Lower price so commission <= threshold (20% of 100 is 20 <= 50)
    @payment.update!(amount: 100.0) # commission 20.0 under 50.0
    commission = CommissionService.process_payment(@payment)
    assert_equal "approved", commission.reload.status
    assert commission.approved_at.present?
  end

  test "process_payment returns nil when no referral" do
    @user.referral.destroy
    assert_nil CommissionService.process_payment(@payment)
  end

  test "approve_commission approves only pending" do
    commission = Commission.create!(
      affiliate: @affiliate,
      payment: @payment,
      referral: @referral,
      amount: 10.0,
      currency: "USD",
      commission_rate: 20.0,
      status: :pending
    )

    assert CommissionService.approve_commission(commission, "ok")
    assert_equal "approved", commission.reload.status

    # Already approved -> returns false
    refute CommissionService.approve_commission(commission)
  end

  test "process_payout marks commissions as paid and returns summary" do
    Rails.application.config.minimum_payout_amount = 10.0

    c1 = Commission.create!(affiliate: @affiliate, payment: @payment, referral: @referral, amount: 12.5, currency: "USD", commission_rate: 20.0, status: :approved)
    c2 = Commission.create!(affiliate: @affiliate, payment: Payment.create!(user: @user, plan: @plan, amount: 50.0, currency: "USD", status: :paid), referral: @referral, amount: 5.0, currency: "USD", commission_rate: 10.0, status: :approved)

    summary = CommissionService.process_payout(@affiliate)
    assert summary.is_a?(Hash)
    assert_equal @affiliate, summary[:affiliate]
    assert_in_delta 17.5, summary[:amount].to_f, 0.01
    assert_equal 2, summary[:commission_count]
    assert_match /PAYOUT-/, summary[:transaction_id]

    assert_equal "paid", c1.reload.status
    assert_equal "paid", c2.reload.status
    assert c1.paid_at.present?
    assert c2.paid_at.present?
  end

  test "process_payout returns nil when below minimum threshold" do
    Rails.application.config.minimum_payout_amount = 1000.0
    Commission.create!(affiliate: @affiliate, payment: @payment, referral: @referral, amount: 10.0, currency: "USD", commission_rate: 20.0, status: :approved)
    assert_nil CommissionService.process_payout(@affiliate)
  end

  test "process_payout filters by commission_ids when provided" do
    Rails.application.config.minimum_payout_amount = 1.0
    c1 = Commission.create!(affiliate: @affiliate, payment: @payment, referral: @referral, amount: 3.0, currency: "USD", commission_rate: 20.0, status: :approved)
    c2 = Commission.create!(affiliate: @affiliate, payment: Payment.create!(user: @user, plan: @plan, amount: 40.0, currency: "USD", status: :paid), referral: @referral, amount: 4.0, currency: "USD", commission_rate: 10.0, status: :approved)

    summary = CommissionService.process_payout(@affiliate, [ c1.id ])
    assert_equal 1, summary[:commission_count]
    assert_equal 3.0, summary[:amount]
    assert_equal "paid", c1.reload.status
    assert_equal "approved", c2.reload.status
  end

  test "cancel_referral_commissions rejects referral and cancels pending commissions" do
    commission = Commission.create!(affiliate: @affiliate, payment: @payment, referral: @referral, amount: 5.0, currency: "USD", commission_rate: 20.0, status: :pending)
    CommissionService.cancel_referral_commissions(@referral, "fraud suspected")
    assert_equal "rejected", @referral.reload.status
    assert_equal "cancelled", commission.reload.status
  end
end
