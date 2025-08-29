require "test_helper"

class PaymentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.instance_variable_get(:@issued_passphrase)
    @plan = plans(:monthly)

    # Login the user with passphrase
    sign_in_user
  end

  def sign_in_user
    post session_path, params: { passphrase: "#{@passphrase}:password" }
  end

  test "should redirect to login when not authenticated" do
    delete session_path

    post plan_payments_path(@plan), params: { crypto: "btc" }
    assert_redirected_to new_session_path
  end

  test "should create payment with valid crypto" do
    mock_response = {
      "id" => "processor_123",
      "wallet" => "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
      "amount" => "0.0012345"
    }

    PaymentProcessor.stubs(:create_payment).returns(mock_response)

    assert_difference "Payment.count", 1 do
      post plan_payments_path(@plan), params: { crypto: "btc" }
    end

    payment = Payment.order(:created_at).last
    assert_equal @user, payment.user
    assert_equal @plan, payment.plan
    assert_equal "btc", payment.crypto_currency
    assert_equal "0.0012345", payment.crypto_amount.to_s
    assert_equal "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", payment.payment_address
    assert_equal "processor_123", payment.processor_id
    assert_redirected_to payment_path(payment)
  end

  test "should handle payment processor API failure" do
    PaymentProcessor.stubs(:create_payment).raises("API Error")

    assert_no_difference "Payment.count" do
      post plan_payments_path(@plan), params: { crypto: "btc" }
    end

    assert_redirected_to plan_path(@plan)
    assert_match "Unable to create payment:", flash[:alert]
  end

  test "should show payment" do
    payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      crypto_currency: "btc",
      crypto_amount: 0.0012345,
      payment_address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
      processor_id: "test123",
      expires_at: 1.hour.from_now
    )

    get payment_path(payment)
    assert_response :success
    assert_select "input[value=?]", payment.payment_address
  end

  test "should only show own payments" do
    other_user = users(:two)

    # Make sure we're using other_user's association to create the payment
    payment = Payment.create!(
      user: other_user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      processor_id: "test456",
      expires_at: 1.hour.from_now
    )

    # Verify the payment belongs to other_user
    assert_equal other_user.id, payment.user_id
    assert_not_equal @user.id, payment.user_id

    # Trying to access other user's payment should fail
    get payment_path(payment)

    # Should return 404 since the payment doesn't belong to current user
    assert_response :not_found
  end

  test "should check payment status on show page" do
    payment = Payment.create!(
      user: @user,
      plan: @plan,
      amount: @plan.price,
      currency: "USD",
      crypto_currency: "btc",
      processor_id: "shkeeper_123",
      status: :pending
    )

    mock_status = {
      "status" => "PAID",
      "amount_received" => "0.0012345"
    }

    PaymentProcessor.stubs(:get_payment_status).returns(mock_status)

    get payment_path(payment)

    # Should redirect to subscriptions after successful payment
    assert_redirected_to subscriptions_path
    assert_equal "Payment completed successfully!", flash[:notice]
  end
end
