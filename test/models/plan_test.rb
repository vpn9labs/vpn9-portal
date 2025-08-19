require "test_helper"

class PlanTest < ActiveSupport::TestCase
  def setup
    @plan = Plan.new(
      name: "Test Plan",
      description: "Test description",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      active: true,
      features: [ "Feature 1", "Feature 2" ],
      device_limit: 5
    )
  end

  test "should be valid with valid attributes" do
    assert @plan.valid?
  end

  test "should require name" do
    @plan.name = nil
    assert_not @plan.valid?
    assert_includes @plan.errors[:name], "can't be blank"
  end

  test "should require price" do
    @plan.price = nil
    assert_not @plan.valid?
    assert_includes @plan.errors[:price], "can't be blank"
  end

  test "should require non-negative price" do
    @plan.price = -1
    assert_not @plan.valid?
    assert_includes @plan.errors[:price], "must be greater than or equal to 0"
  end

  test "should require duration_days" do
    @plan.duration_days = nil
    assert_not @plan.valid?
    assert_includes @plan.errors[:duration_days], "can't be blank"
  end

  test "should require positive duration_days" do
    @plan.duration_days = 0
    assert_not @plan.valid?
    assert_includes @plan.errors[:duration_days], "must be greater than 0"
  end

  test "should have default currency of USD" do
    plan = Plan.new
    assert_equal "USD", plan.currency
  end

  test "should have default active status of true" do
    plan = Plan.new
    assert plan.active
  end

  test "should have active scope" do
    active_plan = Plan.create!(
      name: "Active Plan",
      price: 10,
      duration_days: 30,
      active: true
    )
    inactive_plan = Plan.create!(
      name: "Inactive Plan",
      price: 10,
      duration_days: 30,
      active: false
    )

    assert_includes Plan.active, active_plan
    assert_not_includes Plan.active, inactive_plan
  end

  test "should destroy associated subscriptions" do
    @plan.save!
    user = User.create!(email_address: "test@example.com", password: "password")
    subscription = @plan.subscriptions.create!(
      user: user,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_difference "Subscription.count", -1 do
      @plan.destroy
    end
  end

  test "should destroy associated payments" do
    @plan.save!
    user = User.create!(email_address: "test@example.com", password: "password")
    payment = @plan.payments.create!(
      user: user,
      amount: @plan.price,
      currency: @plan.currency
    )

    assert_difference "Payment.count", -1 do
      @plan.destroy
    end
  end

  # Device Limit Tests
  test "should require device_limit" do
    @plan.device_limit = nil
    assert_not @plan.valid?
    assert_includes @plan.errors[:device_limit], "can't be blank"
  end

  test "should require device_limit to be greater than 0" do
    @plan.device_limit = 0
    assert_not @plan.valid?
    assert_includes @plan.errors[:device_limit], "must be greater than 0"

    @plan.device_limit = -1
    assert_not @plan.valid?
    assert_includes @plan.errors[:device_limit], "must be greater than 0"
  end

  test "should require device_limit to be less than or equal to 100" do
    @plan.device_limit = 101
    assert_not @plan.valid?
    assert_includes @plan.errors[:device_limit], "must be less than or equal to 100"

    @plan.device_limit = 100
    assert @plan.valid?
  end

  test "should display device_limit as number for regular limits" do
    @plan.device_limit = 5
    assert_equal "5", @plan.display_device_limit

    @plan.device_limit = 10
    assert_equal "10", @plan.display_device_limit
  end

  test "should display 'Unlimited' for device_limit of 100" do
    @plan.device_limit = 100
    assert_equal "Unlimited", @plan.display_device_limit
  end
end
