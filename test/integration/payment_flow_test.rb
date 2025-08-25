require "test_helper"

class PaymentFlowTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.instance_variable_get(:@issued_passphrase)
    @plan = plans(:monthly)

    # Mock payment processor responses
    @mock_cryptos = {
      "btc" => { "name" => "Bitcoin", "enabled" => true },
      "eth" => { "name" => "Ethereum", "enabled" => true }
    }

    @mock_payment_response = {
      "id" => "processor_payment_123",
      "wallet" => "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
      "amount" => "0.0012345"
    }
  end

  test "complete payment flow from plan selection to subscription activation" do
    # Step 1: User logs in
    post session_path, params: { passphrase: "#{@passphrase}:password" }
    follow_redirect!
    assert_response :success

    # Step 2: User views plans
    get plans_path
    assert_response :success
    assert_select "h2", "VPN Subscription Plans"
    assert_match @plan.name, response.body

    # Step 3: User selects a plan
    PaymentProcessor.stubs(:available_cryptos).returns(@mock_cryptos)

    get plan_path(@plan)
    assert_response :success
    assert_match "Bitcoin", response.body
    assert_match "Ethereum", response.body

    # Step 4: User initiates payment with Bitcoin
    PaymentProcessor.stubs(:create_payment).returns(@mock_payment_response)

    assert_difference "Payment.count", 1 do
      post plan_payments_path(@plan), params: { crypto: "btc" }
    end

    payment = Payment.last
    assert_equal @user, payment.user
    assert_equal @plan, payment.plan
    assert_equal "pending", payment.status
    assert_equal "btc", payment.crypto_currency
    assert_equal "0.0012345", payment.crypto_amount.to_s

    follow_redirect!
    assert_response :success
    assert_match payment.payment_address, response.body

    # Step 5: Simulate webhook from payment processor
    assert_no_difference "Subscription.count" do
      post webhook_payments_path, params: {
        external_id: payment.id.to_s,
        status: "PARTIAL",
        crypto_currency: "btc",
        crypto_amount: "0.0012345",
        amount_received: "0.0006000"
      }
    end

    payment.reload
    assert_equal "partial", payment.status

    # Step 6: Payment completes
    assert_difference "Subscription.count", 1 do
      post webhook_payments_path, params: {
        external_id: payment.id.to_s,
        status: "PAID",
        crypto_currency: "btc",
        crypto_amount: "0.0012345",
        amount_received: "0.0012345",
        transaction_id: "abc123def456"
      }
    end

    payment.reload
    assert_equal "paid", payment.status
    assert_not_nil payment.paid_at

    # Step 7: Verify subscription created
    subscription = @user.subscriptions.last
    assert_not_nil subscription
    assert_equal @plan, subscription.plan
    assert_equal "active", subscription.status
    assert subscription.active?

    # Step 8: User views subscription
    get subscriptions_path
    assert_response :success
    assert_match "Active Subscription", response.body
    assert_match @plan.name, response.body
    assert_match "#{subscription.days_remaining} days remaining", response.body
  end

  test "payment extension flow for existing subscription" do
    # Create existing subscription
    existing_subscription = Subscription.create!(
      user: @user,
      plan: @plan,
      status: :active,
      started_at: 20.days.ago,
      expires_at: 10.days.from_now
    )

    post session_path, params: { passphrase: "#{@passphrase}:password" }

    # User initiates another payment
    PaymentProcessor.stubs(:create_payment).returns(@mock_payment_response)

    post plan_payments_path(@plan), params: { crypto: "btc" }
    payment = Payment.last

    original_expires_at = existing_subscription.expires_at

    # Complete payment
    post webhook_payments_path, params: {
      external_id: payment.id.to_s,
      status: "PAID",
      transaction_id: "test123"
    }

    existing_subscription.reload
    # Allow for small timing differences during test execution
    expected_expires_at = original_expires_at + @plan.duration_days.days
    actual_difference = (existing_subscription.expires_at - original_expires_at).to_i
    expected_difference = @plan.duration_days.days.to_i
    assert_equal expected_difference, actual_difference, "Subscription should be extended by exactly #{@plan.duration_days} days"
  end

  test "failed payment flow" do
    post session_path, params: { passphrase: "#{@passphrase}:password" }

    # API failure during payment creation
    PaymentProcessor.stubs(:create_payment).raises("API Error")

    assert_no_difference "Payment.count" do
      post plan_payments_path(@plan), params: { crypto: "btc" }
    end

    assert_redirected_to plan_path(@plan)
    follow_redirect!
    assert_match "Unable to create payment", response.body
  end

  test "expired payment flow" do
    post session_path, params: { passphrase: "#{@passphrase}:password" }

    PaymentProcessor.stubs(:create_payment).returns(@mock_payment_response)

    post plan_payments_path(@plan), params: { crypto: "btc" }
    payment = Payment.last

    # Simulate expired payment
    assert_no_difference "Subscription.count" do
      post webhook_payments_path, params: {
        external_id: payment.id.to_s,
        status: "EXPIRED"
      }
    end

    payment.reload
    assert_equal "expired", payment.status
    assert_nil payment.subscription
  end
end
