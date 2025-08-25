require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Create user and capture the passphrase
    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.regenerate_passphrase!

    @plan = plans(:monthly)
    @subscription = Subscription.create!(
      user: @user,
      plan: @plan,
      status: :active,
      started_at: 10.days.ago,
      expires_at: 20.days.from_now
    )

    # Create some payments
    Payment.create!(
      user: @user,
      plan: @plan,
      subscription: @subscription,
      amount: @plan.price,
      currency: "USD",
      status: :paid,
      paid_at: 10.days.ago
    )

    # Login the user with passphrase
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }
  end

  test "should get index" do
    get subscriptions_path
    assert_response :success
    assert_select "h2", "My Subscription"
  end

  test "should show current subscription" do
    get subscriptions_path
    assert_response :success
    assert_match @plan.name, response.body
    assert_match "Active", response.body
    assert_match "#{@subscription.days_remaining} days remaining", response.body
  end

  test "should show no subscription message when none exists" do
    @subscription.destroy

    get subscriptions_path
    assert_response :success
    assert_match "You don't have an active subscription", response.body
    assert_select "a[href=?]", plans_path, text: "View available plans"
  end

  test "should show recent payments" do
    get subscriptions_path
    assert_response :success
    assert_select "h3", text: "Recent Payments"
    # Check that we have at least one payment in the list
    assert_select "div.bg-white.shadow ul.divide-y li", minimum: 1
  end

  test "should show past subscriptions" do
    @subscription.update!(status: :expired, expires_at: 1.day.ago)

    get subscriptions_path
    assert_response :success
    assert_select "h3", text: "Past Subscriptions"
    # Since we're testing past subscriptions specifically, verify the content exists
    assert_match @subscription.plan.name, response.body
  end

  test "should get show" do
    get subscription_path(@subscription)
    assert_response :success
    assert_match @plan.name, response.body
  end

  test "should only show own subscriptions" do
    other_user = users(:two)
    other_subscription = Subscription.create!(
      user: other_user,
      plan: @plan,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    get subscription_path(other_subscription)
    assert_redirected_to root_path
    assert_equal "Subscription not found", flash[:alert]
  end

  test "should cancel subscription" do
    assert_equal "active", @subscription.status

    post cancel_subscription_path(@subscription)

    @subscription.reload
    assert_equal "cancelled", @subscription.status
    assert_not_nil @subscription.cancelled_at
    assert_redirected_to subscriptions_path
    assert_equal "Subscription cancelled successfully", flash[:notice]
  end

  test "should not cancel already cancelled subscription" do
    @subscription.update!(status: :cancelled, cancelled_at: 1.day.ago)

    post cancel_subscription_path(@subscription)

    assert_redirected_to subscriptions_path
    assert_equal "Subscription is already cancelled", flash[:alert]
  end

  test "should redirect to login when not authenticated" do
    delete session_path

    get subscriptions_path
    assert_redirected_to new_session_path
  end
end
