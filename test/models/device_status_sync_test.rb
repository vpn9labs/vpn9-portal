require "test_helper"

class DeviceStatusSyncTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email_address: "status@example.com", password: "password")
    @plan_basic = Plan.create!(name: "Basic", price: 5.0, duration_days: 30, device_limit: 2)
  end

  test "devices are inactive without active subscription" do
    d1 = @user.devices.create!(public_key: "k1")
    d2 = @user.devices.create!(public_key: "k2")

    assert_equal "inactive", d1.reload.status
    assert_equal "inactive", d2.reload.status
  end

  test "activates up to device_limit when subscription active" do
    d1 = @user.devices.create!(public_key: "k1")
    d2 = @user.devices.create!(public_key: "k2")
    d3 = @user.devices.create!(public_key: "k3")

    # Activate subscription
    Subscription.create!(
      user: @user,
      plan: @plan_basic,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_equal %w[active active inactive], [ d1.reload.status, d2.reload.status, d3.reload.status ]
  end

  test "deactivates all devices when subscription cancelled" do
    d1 = @user.devices.create!(public_key: "k1")
    d2 = @user.devices.create!(public_key: "k2")

    sub = Subscription.create!(
      user: @user,
      plan: @plan_basic,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_equal %w[active active], [ d1.reload.status, d2.reload.status ]

    sub.cancel!
    assert_equal %w[inactive inactive], [ d1.reload.status, d2.reload.status ]
  end

  test "honors plan changes to device_limit" do
    # Start with 1-device plan
    plan_one = Plan.create!(name: "One", price: 3.0, duration_days: 30, device_limit: 1)
    d1 = @user.devices.create!(public_key: "k1")
    d2 = @user.devices.create!(public_key: "k2")

    sub = Subscription.create!(
      user: @user,
      plan: plan_one,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_equal %w[active inactive], [ d1.reload.status, d2.reload.status ]

    # Upgrade plan to allow 2 devices
    sub.update!(plan: @plan_basic)
    assert_equal %w[active active], [ d1.reload.status, d2.reload.status ]
  end

  test "activates next device when one is removed" do
    d1 = @user.devices.create!(public_key: "k1")
    d2 = @user.devices.create!(public_key: "k2")
    d3 = @user.devices.create!(public_key: "k3")
    Subscription.create!(
      user: @user,
      plan: @plan_basic,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_equal %w[active active inactive], [ d1.reload.status, d2.reload.status, d3.reload.status ]

    d1.destroy
    assert_equal %w[active active], [ d2.reload.status, d3.reload.status ]
  end
end
