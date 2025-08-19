require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email_address: "test@example.com", password: "password")
    @plan = Plan.create!(
      name: "Test Plan",
      price: 9.99,
      duration_days: 30
    )
    @payment = Payment.new(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD"
    )
  end

  test "should be valid with valid attributes" do
    assert @payment.valid?
  end

  test "should require user" do
    @payment.user = nil
    assert_not @payment.valid?
    assert_includes @payment.errors[:user], "must exist"
  end

  test "should require plan" do
    @payment.plan = nil
    assert_not @payment.valid?
    assert_includes @payment.errors[:plan], "must exist"
  end

  test "should require amount" do
    @payment.amount = nil
    assert_not @payment.valid?
    assert_includes @payment.errors[:amount], "can't be blank"
  end

  test "should require positive amount" do
    @payment.amount = 0
    assert_not @payment.valid?
    assert_includes @payment.errors[:amount], "must be greater than 0"
  end

  test "should require currency" do
    @payment.currency = nil
    assert_not @payment.valid?
    assert_includes @payment.errors[:currency], "can't be blank"
  end

  test "should default to pending status" do
    payment = Payment.new
    assert_equal "pending", payment.status
  end

  test "should not require expires_at" do
    @payment.save!
    # Payment expires_at is optional and may not be set on creation
    assert @payment.valid?
  end

  test "pending? should return true for pending status" do
    @payment.status = :pending
    assert @payment.pending?
  end

  test "successful? should return true for paid and overpaid statuses" do
    @payment.status = :paid
    assert @payment.successful?

    @payment.status = :overpaid
    assert @payment.successful?

    @payment.status = :pending
    assert_not @payment.successful?
  end

  test "process_webhook should update payment details" do
    @payment.save!
    webhook_data = {
      "status" => "PAID",
      "crypto_currency" => "BTC",
      "crypto_amount" => "0.0012345",
      "crypto_address" => "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
      "transaction_id" => "abc123",
      "amount_received" => "0.0012345"
    }

    @payment.update_from_webhook!(webhook_data)

    assert_equal "paid", @payment.status
    assert_equal webhook_data, @payment.processor_data
  end

  test "process_completion! should create subscription for new user" do
    @payment.status = :paid
    @payment.save!

    assert_nil @user.subscriptions.current.first

    assert_difference "Subscription.count", 1 do
      @payment.process_completion!
    end

    subscription = @user.subscriptions.current.first
    assert_not_nil subscription
    assert_equal @plan, subscription.plan
    assert_equal "active", subscription.status
    assert_equal @payment, subscription.payments.first
    assert_not_nil @payment.paid_at
  end

  test "process_completion! should extend existing subscription" do
    existing_sub = Subscription.create!(
      user: @user,
      plan: @plan,
      status: :active,
      started_at: 10.days.ago,
      expires_at: 20.days.from_now
    )

    @payment.status = :paid
    @payment.save!

    original_expires_at = existing_sub.expires_at

    assert_no_difference "Subscription.count" do
      @payment.process_completion!
    end

    existing_sub.reload
    expected_expires_at = original_expires_at + @plan.duration_days.days
    assert_in_delta expected_expires_at.to_i, existing_sub.expires_at.to_i, 1
  end

  test "process_completion! should not process if not successful" do
    @payment.status = :pending
    @payment.save!

    assert_no_difference "Subscription.count" do
      @payment.process_completion!
    end
  end

  test "pending scope should include pending payments" do
    @payment.save!
    paid_payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      status: :paid
    )

    assert_includes Payment.pending, @payment
    assert_not_includes Payment.pending, paid_payment
  end

  test "successful scope should include paid and overpaid payments" do
    @payment.status = :paid
    @payment.save!

    overpaid_payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      status: :overpaid
    )

    pending_payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      status: :pending
    )

    assert_includes Payment.successful, @payment
    assert_includes Payment.successful, overpaid_payment
    assert_not_includes Payment.successful, pending_payment
  end
end
