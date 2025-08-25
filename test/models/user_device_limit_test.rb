require "test_helper"

class UserDeviceLimitTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    # Clear any existing devices from fixtures
    @user.devices.destroy_all

    @plan_basic = plans(:basic_3)

    @plan_pro = plans(:pro_10)

    @plan_unlimited = plans(:unlimited_100)
  end

  # Device Limit Method Tests
  test "should return default device limit when no subscription" do
    assert_equal User::DEFAULT_DEVICE_LIMIT, @user.device_limit
    assert_equal 5, @user.device_limit
  end

  test "should return plan device limit when subscription exists" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_basic,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_equal 3, @user.device_limit
  end

  test "should return plan device limit for different plans" do
    # Test with Pro plan
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_pro,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_equal 10, @user.device_limit

    # Update to Unlimited plan
    subscription.update!(plan: @plan_unlimited)
    assert_equal 100, @user.device_limit
  end

  test "should return default limit when subscription is expired" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_pro,
      status: :expired,
      started_at: 31.days.ago,
      expires_at: 1.day.ago
    )

    assert_equal User::DEFAULT_DEVICE_LIMIT, @user.device_limit
  end

  test "should return default limit when subscription is cancelled" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_pro,
      status: :cancelled,
      started_at: Time.current,
      expires_at: 30.days.from_now,
      cancelled_at: Time.current
    )

    assert_equal User::DEFAULT_DEVICE_LIMIT, @user.device_limit
  end

  # Can Add Device Tests
  test "can_add_device? should return true when under limit" do
    assert_equal 0, @user.devices.count
    assert @user.can_add_device?

    @user.devices.create!(public_key: "test_key_1")
    assert @user.can_add_device?
  end

  test "can_add_device? should return false when at limit" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_basic,  # 3 device limit
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 3 devices (at limit)
    3.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    assert_equal 3, @user.devices.count
    assert_equal 3, @user.device_limit
    assert_not @user.can_add_device?
  end

  test "can_add_device? should handle limit changes when plan changes" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_basic,  # 3 device limit
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 3 devices (at basic limit)
    3.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    assert_not @user.can_add_device?

    # Upgrade to Pro plan
    subscription.update!(plan: @plan_pro)  # 10 device limit
    assert @user.can_add_device?

    # Add more devices
    5.times do |i|
      @user.devices.create!(public_key: "test_key_pro_#{i}")
    end

    assert_equal 8, @user.devices.count
    assert @user.can_add_device?
  end

  # Devices Remaining Tests
  test "devices_remaining should return correct count" do
    assert_equal 5, @user.devices_remaining

    @user.devices.create!(public_key: "test_key_1")
    assert_equal 4, @user.devices_remaining

    @user.devices.create!(public_key: "test_key_2")
    assert_equal 3, @user.devices_remaining
  end

  test "devices_remaining should never return negative" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_basic,  # 3 device limit
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 3 devices
    3.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    assert_equal 0, @user.devices_remaining

    # Try to go over limit (shouldn't happen in practice due to validation)
    @user.devices.create!(public_key: "test_key_extra", name: "force-created")
    @user.reload

    # Should still return 0, not negative
    assert_equal 0, @user.devices_remaining
  end

  test "devices_remaining with different subscription plans" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_pro,  # 10 device limit
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    assert_equal 10, @user.devices_remaining

    # Add 5 devices
    5.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    assert_equal 5, @user.devices_remaining

    # Switch to unlimited plan
    subscription.update!(plan: @plan_unlimited)
    assert_equal 95, @user.devices_remaining  # 100 - 5
  end

  # Edge Cases
  test "should handle user with no devices" do
    assert_equal 0, @user.devices.count
    assert_equal 5, @user.device_limit
    assert @user.can_add_device?
    assert_equal 5, @user.devices_remaining
  end

  test "should handle user with multiple expired subscriptions" do
    # Create expired subscription
    old_subscription = Subscription.create!(
      user: @user,
      plan: @plan_pro,
      status: :expired,
      started_at: 60.days.ago,
      expires_at: 30.days.ago
    )

    # Create another expired subscription
    another_old = Subscription.create!(
      user: @user,
      plan: @plan_unlimited,
      status: :expired,
      started_at: 90.days.ago,
      expires_at: 60.days.ago
    )

    # Should use default limit
    assert_equal User::DEFAULT_DEVICE_LIMIT, @user.device_limit
  end

  test "should handle subscription without plan" do
    subscription = Subscription.create!(
      user: @user,
      plan: @plan_basic,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Simulate plan deletion (shouldn't happen in practice)
    @plan_basic.destroy
    @user.reload

    # Should fall back to default
    assert_equal User::DEFAULT_DEVICE_LIMIT, @user.device_limit
  end

  test "should correctly report device limits for fixtures" do
    user_two = users(:two)
    user_two.devices.destroy_all

    # User without subscription
    assert_equal User::DEFAULT_DEVICE_LIMIT, user_two.device_limit
    assert user_two.can_add_device?

    # Add devices up to limit
    5.times do |i|
      user_two.devices.create!(public_key: "user_two_key_#{i}")
    end

    assert_not user_two.can_add_device?
    assert_equal 0, user_two.devices_remaining
  end
end
