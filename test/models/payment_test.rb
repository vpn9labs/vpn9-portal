require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @plan = plans(:monthly)
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

    @payment.update_from_webhook!(webhook_data, "127.0.0.1")

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

  # Tests for update_status! method
  test "update_status! should update status to paid when PAID" do
    @payment.save!
    @payment.update_status!("PAID")
    assert_equal "paid", @payment.status
  end

  test "update_status! should update status to partial when PARTIAL" do
    @payment.save!
    @payment.update_status!("PARTIAL")
    assert_equal "partial", @payment.status
  end

  test "update_status! should update status to overpaid when OVERPAID" do
    @payment.save!
    @payment.update_status!("OVERPAID")
    assert_equal "overpaid", @payment.status
  end

  test "update_status! should update status to expired when EXPIRED" do
    @payment.save!
    @payment.update_status!("EXPIRED")
    assert_equal "expired", @payment.status
  end

  test "update_status! should update status to failed for unknown status" do
    @payment.save!
    @payment.update_status!("UNKNOWN")
    assert_equal "failed", @payment.status
  end

  test "update_status! should call check_for_successful_payment!" do
    @payment.save!
    @payment.expects(:check_for_successful_payment!)
    @payment.update_status!("PAID")
  end

  test "update_status! should persist the changes" do
    @payment.save!
    @payment.update_status!("PAID")
    @payment.reload
    assert_equal "paid", @payment.status
  end

  # Tests for update_from_webhook! method
  test "update_from_webhook! should create webhook log" do
    @payment.save!
    webhook_data = {
      "status" => "PAID",
      "transaction_id" => "TX123"
    }

    assert_difference "WebhookLog.count", 1 do
      @payment.update_from_webhook!(webhook_data, "192.168.1.1")
    end

    log = @payment.webhook_logs.last
    assert_equal "PAID", log.status
    assert_equal "192.168.1.1", log.ip_address
    assert_not_nil log.processed_at
  end

  test "update_from_webhook! should store transaction_id" do
    @payment.save!
    webhook_data = {
      "status" => "PAID",
      "transaction_id" => "TX12345"
    }

    @payment.update_from_webhook!(webhook_data, "127.0.0.1")
    assert_equal "TX12345", @payment.transaction_id
  end

  test "update_from_webhook! should store processor_data" do
    @payment.save!
    webhook_data = {
      "status" => "PAID",
      "transaction_id" => "TX123",
      "crypto_currency" => "BTC",
      "crypto_amount" => "0.001"
    }

    @payment.update_from_webhook!(webhook_data, "127.0.0.1")
    assert_equal webhook_data, @payment.processor_data
  end

  test "update_from_webhook! should prevent replay attacks" do
    @payment.save!
    webhook_data = {
      "status" => "PAID",
      "transaction_id" => "TX123"
    }

    # First webhook should succeed
    @payment.update_from_webhook!(webhook_data, "127.0.0.1")

    # Second webhook with same status should raise error
    assert_raises(RuntimeError, "Duplicate webhook detected") do
      @payment.update_from_webhook!(webhook_data, "127.0.0.1")
    end
  end

  test "update_from_webhook! should allow different status updates" do
    @payment.save!

    # First webhook - partial payment
    webhook_data1 = {
      "status" => "PARTIAL",
      "transaction_id" => "TX123"
    }
    @payment.update_from_webhook!(webhook_data1, "127.0.0.1")
    assert_equal "partial", @payment.status

    # Second webhook - paid (different status, should be allowed)
    webhook_data2 = {
      "status" => "PAID",
      "transaction_id" => "TX123"
    }
    assert_nothing_raised do
      @payment.update_from_webhook!(webhook_data2, "127.0.0.1")
    end
    assert_equal "paid", @payment.status
  end

  test "update_from_webhook! should call check_for_successful_payment!" do
    @payment.save!
    webhook_data = {
      "status" => "PAID",
      "transaction_id" => "TX123"
    }

    # check_for_successful_payment! is called once in update_status!
    @payment.expects(:check_for_successful_payment!).once
    @payment.update_from_webhook!(webhook_data, "127.0.0.1")
  end

  # Tests for check_for_successful_payment! method
  test "check_for_successful_payment! should process completion for paid payment" do
    @payment.status = :paid
    @payment.save!

    @payment.expects(:process_completion!)
    CommissionService.expects(:process_payment).with(@payment)

    @payment.check_for_successful_payment!
  end

  test "check_for_successful_payment! should process completion for overpaid payment" do
    @payment.status = :overpaid
    @payment.save!

    @payment.expects(:process_completion!)
    CommissionService.expects(:process_payment).with(@payment)

    @payment.check_for_successful_payment!
  end

  test "check_for_successful_payment! should not process for pending payment" do
    @payment.status = :pending
    @payment.save!

    @payment.expects(:process_completion!).never
    CommissionService.expects(:process_payment).never

    @payment.check_for_successful_payment!
  end

  test "check_for_successful_payment! should not process for failed payment" do
    @payment.status = :failed
    @payment.save!

    @payment.expects(:process_completion!).never
    CommissionService.expects(:process_payment).never

    @payment.check_for_successful_payment!
  end
end
