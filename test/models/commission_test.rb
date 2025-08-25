require "test_helper"

class CommissionTest < ActiveSupport::TestCase
  def setup
    @affiliate = Affiliate.create!(
      name: "Test Affiliate",
      email: "affiliate@example.com",
      code: "TESTCODE",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "btc",
      payout_address: "bc1qtest123"
    )

    @user = users(:one)
    @plan = plans(:pro_5)

    @payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: 100,
      currency: "USD",
      status: :paid
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

  # === Validations ===

  test "should be valid with valid attributes" do
    assert @commission.valid?
  end

  test "should require affiliate" do
    @commission.affiliate = nil
    assert_not @commission.valid?
    assert_includes @commission.errors[:affiliate], "must exist"
  end

  test "should require payment" do
    @commission.payment = nil
    assert_not @commission.valid?
    assert_includes @commission.errors[:payment], "must exist"
  end

  test "should require referral" do
    @commission.referral = nil
    assert_not @commission.valid?
    assert_includes @commission.errors[:referral], "must exist"
  end

  test "should require amount" do
    @commission.amount = nil
    assert_not @commission.valid?
    assert_includes @commission.errors[:amount], "can't be blank"
  end

  test "should require positive amount" do
    @commission.amount = 0
    assert_not @commission.valid?
    assert_includes @commission.errors[:amount], "must be greater than 0"

    @commission.amount = -10
    assert_not @commission.valid?
    assert_includes @commission.errors[:amount], "must be greater than 0"
  end

  test "should require currency" do
    @commission.currency = nil
    assert_not @commission.valid?
    assert_includes @commission.errors[:currency], "can't be blank"
  end

  test "should require commission_rate" do
    @commission.commission_rate = nil
    assert_not @commission.valid?
    assert_includes @commission.errors[:commission_rate], "can't be blank"
  end

  test "should validate commission_rate range" do
    @commission.commission_rate = -1
    assert_not @commission.valid?
    assert_includes @commission.errors[:commission_rate], "must be in 0..100"

    @commission.commission_rate = 101
    assert_not @commission.valid?
    assert_includes @commission.errors[:commission_rate], "must be in 0..100"

    @commission.commission_rate = 50
    assert @commission.valid?
  end

  test "should enforce unique payment_id" do
    duplicate = @commission.dup
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:payment_id], "has already been taken"
  end

  # === Scopes ===

  test "payable scope should return approved unpaid commissions" do
    @commission.approve!
    assert_includes Commission.payable, @commission

    @commission.mark_as_paid!
    assert_not_includes Commission.payable, @commission
  end

  test "recent scope should order by created_at desc" do
    older = Commission.create!(
      affiliate: @affiliate,
      payment: Payment.create!(user: @user, plan: @plan, amount: 50, currency: "USD", status: :paid),
      referral: @referral,
      amount: 10,
      currency: "USD",
      commission_rate: 20,
      created_at: 2.days.ago
    )

    recent = Commission.recent
    assert_equal @commission, recent.first
    assert_equal older, recent.second
  end

  test "by_status scope should filter by status" do
    @commission.update!(status: :approved)

    pending_commission = Commission.create!(
      affiliate: @affiliate,
      payment: Payment.create!(user: @user, plan: @plan, amount: 50, currency: "USD", status: :paid),
      referral: @referral,
      amount: 10,
      currency: "USD",
      commission_rate: 20,
      status: :pending
    )

    assert_includes Commission.by_status(:approved), @commission
    assert_not_includes Commission.by_status(:approved), pending_commission
    assert_includes Commission.by_status(:pending), pending_commission
  end

  test "for_period scope should filter by date range" do
    old_commission = Commission.create!(
      affiliate: @affiliate,
      payment: Payment.create!(user: @user, plan: @plan, amount: 50, currency: "USD", status: :paid),
      referral: @referral,
      amount: 10,
      currency: "USD",
      commission_rate: 20,
      created_at: 1.month.ago
    )

    start_date = 1.week.ago
    end_date = Date.current

    assert_includes Commission.for_period(start_date, end_date), @commission
    assert_not_includes Commission.for_period(start_date, end_date), old_commission
  end

  # === Status Methods ===

  test "approve! should change status to approved" do
    assert @commission.pending?

    @commission.approve!
    assert @commission.approved?
    assert_not_nil @commission.approved_at
    assert @commission.approved_at <= Time.current
  end

  test "approve! should add admin notes" do
    @commission.approve!("Manually approved by admin")
    assert_includes @commission.notes, "Manually approved by admin"
  end

  test "approve! should not work on already approved commission" do
    @commission.approve!
    approved_at = @commission.approved_at

    @commission.approve!("Second approval")
    assert_equal approved_at, @commission.approved_at
    assert_not_includes @commission.notes.to_s, "Second approval"
  end

  test "approve! should not work on paid commission" do
    @commission.update!(status: :paid)

    @commission.approve!
    assert @commission.paid?
    assert_not @commission.approved?
  end

  test "cancel! should change status to cancelled" do
    assert @commission.pending?

    @commission.cancel!
    assert @commission.cancelled?
  end

  test "cancel! should add cancellation reason" do
    @commission.cancel!("Fraudulent activity detected")
    assert_includes @commission.notes, "Fraudulent activity detected"
  end

  test "cancel! should not work on already cancelled commission" do
    @commission.cancel!("First cancel")
    @commission.cancel!("Second cancel")

    assert_equal 1, @commission.notes.scan("First cancel").count
    assert_equal 0, @commission.notes.scan("Second cancel").count
  end

  test "mark_as_paid! should change status to paid" do
    @commission.approve!

    @commission.mark_as_paid!("TXN123")
    assert @commission.paid?
    assert_not_nil @commission.paid_at
    assert_equal "TXN123", @commission.payout_transaction_id
  end

  test "mark_as_paid! should not work on already paid commission" do
    @commission.mark_as_paid!("TXN123")
    paid_at = @commission.paid_at

    @commission.mark_as_paid!("TXN456")
    assert_equal paid_at, @commission.paid_at
    assert_equal "TXN123", @commission.payout_transaction_id
  end

  # === Callbacks ===

  test "should set commission_rate from affiliate on create" do
    commission = Commission.new(
      affiliate: @affiliate,
      payment: Payment.create!(user: @user, plan: @plan, amount: 75, currency: "USD", status: :paid),
      referral: @referral,
      amount: 15,
      currency: "USD"
    )

    assert_nil commission.commission_rate
    commission.save!
    assert_equal @affiliate.commission_rate, commission.commission_rate
  end

  test "should update affiliate balance on create" do
    initial_pending = @affiliate.pending_balance
    initial_lifetime = @affiliate.lifetime_earnings

    new_commission = Commission.create!(
      affiliate: @affiliate,
      payment: Payment.create!(user: @user, plan: @plan, amount: 200, currency: "USD", status: :paid),
      referral: @referral,
      amount: 40,
      currency: "USD",
      commission_rate: 20,
      status: :pending
    )

    @affiliate.reload
    # pending_balance is calculated from pending commissions
    assert_equal initial_pending + 40, @affiliate.pending_balance
    # lifetime_earnings is calculated from approved commissions, so shouldn't change for pending
    assert_equal initial_lifetime, @affiliate.lifetime_earnings
  end

  test "should adjust affiliate balance when status changes from pending to cancelled" do
    new_commission = Commission.create!(
      affiliate: @affiliate,
      payment: Payment.create!(user: @user, plan: @plan, amount: 150, currency: "USD", status: :paid),
      referral: @referral,
      amount: 30,
      currency: "USD",
      commission_rate: 20,
      status: :pending
    )

    @affiliate.reload
    initial_pending = @affiliate.pending_balance
    initial_lifetime = @affiliate.lifetime_earnings

    new_commission.cancel!

    @affiliate.reload
    # Cancelled commissions are not included in pending_balance
    assert_equal initial_pending - 30, @affiliate.pending_balance
    # lifetime_earnings only includes approved commissions, so shouldn't change
    assert_equal initial_lifetime, @affiliate.lifetime_earnings
  end

  test "should adjust affiliate balance when status changes from approved to paid" do
    @commission.approve!

    @affiliate.reload
    initial_lifetime = @affiliate.lifetime_earnings  # Now includes the approved commission
    initial_paid = @affiliate.paid_out_total

    @commission.mark_as_paid!

    @affiliate.reload
    # pending_balance calculated from pending commissions (should be 0)
    assert_equal 0, @affiliate.pending_balance
    # paid_out_total now includes this commission
    assert_equal initial_paid + 20, @affiliate.paid_out_total
    # lifetime_earnings stays the same (approved amount doesn't change)
    assert_equal initial_lifetime, @affiliate.lifetime_earnings
  end

  test "should adjust affiliate balance when status changes from approved to cancelled" do
    @commission.approve!

    @affiliate.reload
    initial_lifetime = @affiliate.lifetime_earnings  # Now includes the approved commission

    @commission.cancel!

    @affiliate.reload
    # Cancelled commissions are not included in any balance
    assert_equal 0, @affiliate.pending_balance
    # lifetime_earnings no longer includes cancelled commission
    assert_equal initial_lifetime - 20, @affiliate.lifetime_earnings
  end

  # === Edge Cases ===

  test "should handle decimal amounts correctly" do
    commission = Commission.create!(
      affiliate: @affiliate,
      payment: Payment.create!(user: @user, plan: @plan, amount: 99.99, currency: "USD", status: :paid),
      referral: @referral,
      amount: 19.99,
      currency: "USD",
      commission_rate: 20
    )

    assert_equal BigDecimal("19.99"), commission.amount
  end

  test "should handle multiple currency types" do
    currencies = [ "USD", "EUR", "GBP", "BTC", "ETH" ]

    currencies.each do |currency|
      commission = Commission.create!(
        affiliate: @affiliate,
        payment: Payment.create!(user: @user, plan: @plan, amount: 100, currency: currency, status: :paid),
        referral: @referral,
        amount: 20,
        currency: currency,
        commission_rate: 20
      )

      assert_equal currency, commission.currency
      assert commission.valid?
    end
  end

  test "should maintain data integrity across status transitions" do
    # Track all state changes
    states = []

    states << { status: @commission.status, pending: @affiliate.pending_balance, lifetime: @affiliate.lifetime_earnings }

    @commission.approve!
    @affiliate.reload
    states << { status: @commission.status, pending: @affiliate.pending_balance, lifetime: @affiliate.lifetime_earnings }

    @commission.mark_as_paid!
    @affiliate.reload
    states << { status: @commission.status, pending: @affiliate.pending_balance, lifetime: @affiliate.lifetime_earnings }

    # Verify the progression makes sense
    assert_equal "pending", states[0][:status]
    assert_equal "approved", states[1][:status]
    assert_equal "paid", states[2][:status]

    # Pending balance should decrease when paid
    assert states[2][:pending] < states[0][:pending]
  end

  test "should handle concurrent commission creation" do
    payments = []
    5.times do |i|
      payments << Payment.create!(
        user: @user,
        plan: @plan,
        amount: 100 + i,
        currency: "USD",
        status: :paid
      )
    end

    commissions = []
    threads = payments.map do |payment|
      Thread.new do
        commissions << Commission.create!(
          affiliate: @affiliate,
          payment: payment,
          referral: @referral,
          amount: payment.amount * 0.2,
          currency: "USD",
          commission_rate: 20
        )
      end
    end

    threads.each(&:join)

    assert_equal 5, commissions.compact.count
    assert_equal payments.sum(&:amount) * 0.2, commissions.compact.sum(&:amount)
  end
end
