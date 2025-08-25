require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @plan = plans(:monthly)
    @subscription = Subscription.new(
      user: @user,
      plan: @plan,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )
  end

  test "should be valid with valid attributes" do
    assert @subscription.valid?
  end

  test "should require user" do
    @subscription.user = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:user], "must exist"
  end

  test "should require plan" do
    @subscription.plan = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:plan], "must exist"
  end

  test "should require started_at" do
    @subscription.started_at = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:started_at], "can't be blank"
  end

  test "should require expires_at" do
    @subscription.expires_at = nil
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:expires_at], "can't be blank"
  end

  test "should default to active status" do
    subscription = Subscription.new
    assert_equal "active", subscription.status
  end

  test "should validate expires_at is after started_at" do
    @subscription.expires_at = @subscription.started_at - 1.day
    assert_not @subscription.valid?
    assert_includes @subscription.errors[:expires_at], "must be after the start date"
  end

  test "active? should return true when active and not expired" do
    @subscription.status = :active
    @subscription.expires_at = 1.day.from_now
    assert @subscription.active?
  end

  test "active? should return false when status not active" do
    @subscription.status = :pending
    @subscription.expires_at = 1.day.from_now
    assert_not @subscription.active?
  end

  test "active? should return false when expired" do
    @subscription.status = :active
    @subscription.expires_at = 1.day.ago
    assert_not @subscription.active?
  end

  test "expired? should return true when past expiration date" do
    @subscription.expires_at = 1.day.ago
    assert @subscription.expired?
  end

  test "expired? should return false when before expiration date" do
    @subscription.expires_at = 1.day.from_now
    assert_not @subscription.expired?
  end

  test "days_remaining should calculate correctly" do
    @subscription.expires_at = 10.days.from_now
    assert_in_delta 10, @subscription.days_remaining, 0.1
  end

  test "days_remaining should return 0 when expired" do
    @subscription.expires_at = 1.day.ago
    assert_equal 0, @subscription.days_remaining
  end

  test "current scope should include active non-expired subscriptions" do
    @subscription.status = :active
    @subscription.save!

    expired_sub = Subscription.create!(
      user: @user,
      plan: @plan,
      status: :active,
      started_at: 60.days.ago,
      expires_at: 30.days.ago
    )

    pending_sub = Subscription.create!(
      user: @user,
      plan: @plan,
      status: :pending,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_includes Subscription.current, @subscription
    assert_not_includes Subscription.current, expired_sub
    assert_not_includes Subscription.current, pending_sub
  end

  test "should nullify associated payments on destroy" do
    @subscription.save!
    payment = Payment.create!(
      user: @user,
      plan: @plan,
      subscription: @subscription,
      amount: @plan.price,
      currency: @plan.currency
    )

    assert_no_difference "Payment.count" do
      @subscription.destroy
    end

    assert_nil payment.reload.subscription_id
  end
end
