require "test_helper"

class Payments::BitcartWebhookControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @plan = plans(:monthly)
  end

  test "processes payment update without secret" do
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

    post webhook_payments_path, params: webhook_params
    assert_response :success

    payment.reload
    assert_equal "paid", payment.status
    assert_equal "abc123", payment.transaction_id
  end

  test "returns 404 for invalid payment id" do
    post webhook_payments_path, params: { external_id: "invalid" }
    assert_response :not_found
  end

  test "rejects when secret mismatches" do
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
    assert_equal "pending", payment.reload.status
  end

  test "accepts when secret matches" do
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

  test "successful payment creates subscription" do
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
