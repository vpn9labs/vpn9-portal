require "test_helper"

class PaymentsControllerWebhookTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.instance_variable_get(:@issued_passphrase)
    @plan = Plan.create!(
      name: "Test Plan",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      active: true
    )

    # Login the user with passphrase
    sign_in_user
  end

  def sign_in_user
    post session_path, params: { passphrase: "#{@passphrase}:password" }
  end

  test "webhook should process payment update" do
    payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      status: :pending,
      crypto_currency: "btc",
      processor_id: "test123"
    )

    webhook_params = {
      external_id: payment.id.to_s,
      status: "PAID",
      transaction_id: "abc123"
    }

    # No secret set should still work (legacy behavior)
    post webhook_payments_path, params: webhook_params

    payment.reload
    assert_equal "paid", payment.status
    assert_equal "abc123", payment.transaction_id
    assert_response :success
  end

  test "webhook should ignore invalid payment id" do
    post webhook_payments_path, params: { external_id: "invalid" }
    assert_response :not_found
  end

  test "webhook should reject when secret mismatches" do
    payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      status: :pending,
      crypto_currency: "btc",
      processor_id: "test789",
      webhook_secret: "correct-secret"
    )

    post webhook_payments_path, params: {
      external_id: payment.id.to_s,
      status: "PAID",
      secret: "wrong-secret"
    }

    assert_response :unauthorized
    payment.reload
    assert_equal "pending", payment.status
  end

  test "webhook should accept when secret matches" do
    payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      status: :pending,
      crypto_currency: "btc",
      processor_id: "test790",
      webhook_secret: "correct-secret"
    )

    post webhook_payments_path, params: {
      external_id: payment.id.to_s,
      status: "PAID",
      transaction_id: "zxy987",
      secret: "correct-secret"
    }

    assert_response :success
    payment.reload
    assert_equal "paid", payment.status
    assert_equal "zxy987", payment.transaction_id
  end

  test "successful payment should create subscription" do
    payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      status: :pending
    )

    webhook_params = {
      external_id: payment.id.to_s,
      status: "PAID",
      transaction_id: "test123"
    }

    assert_difference "Subscription.count", 1 do
      post webhook_payments_path, params: webhook_params
    end

    subscription = @user.subscriptions.last
    assert_equal @plan, subscription.plan
    assert_equal "active", subscription.status
  end
end
