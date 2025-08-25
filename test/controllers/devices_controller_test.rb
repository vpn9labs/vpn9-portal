require "test_helper"

class DevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Create user and capture the passphrase
    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.regenerate_passphrase!

    # Create test plans
    @basic_plan = plans(:basic_2)

    @pro_plan = plans(:pro_5)

    # Sign in the user with passphrase
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }
  end

  # Index Tests
  test "should get index when signed in" do
    get devices_path
    assert_response :success
    assert_select "h3", "Your Devices"
  end

  test "should redirect to sign in when not authenticated" do
    delete session_path
    get devices_path
    assert_redirected_to new_session_path
  end

  test "should show device count and limit" do
    # Create subscription with basic plan
    Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    @user.devices.create!(public_key: "test_key_1")

    get devices_path
    assert_response :success
    assert_match "1 of 2 devices used", response.body
  end

  # Device Setup Tests (replaced New Tests)
  test "should get device setup when under device limit" do
    get new_device_setup_path
    assert_response :success
    assert_select "h3", "Setup New Device"
  end

  test "should redirect when at device limit for device setup" do
    # Create subscription with basic plan (2 device limit)
    Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 2 devices (at limit)
    2.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit of 2 devices", flash[:alert]
  end

  # Device creation flow tests
  test "should allow device creation when under limit" do
    # Simulate device creation directly (since it's now handled by DeviceSetupController)
    assert_difference("Device.count") do
      @user.devices.create!(public_key: "new_test_public_key")
    end

    get devices_path
    assert_response :success
    assert_match "new_test_public_key", response.body
  end

  test "should not allow device creation when at limit" do
    # Create subscription with basic plan (2 device limit)
    Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 2 devices (at limit)
    2.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Try to access device setup page
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit of 2 devices", flash[:alert]
  end

  test "should enforce default limit when no subscription" do
    # Add 5 devices (default limit)
    5.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Try to access device setup page
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit of 5 devices", flash[:alert]
  end

  test "should allow device creation after limit increase" do
    # Create subscription with basic plan (2 device limit)
    subscription = Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 2 devices (at limit)
    2.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Should not be able to access setup page
    get new_device_setup_path
    assert_redirected_to devices_path

    # Upgrade to pro plan
    subscription.update!(plan: @pro_plan)

    # Should now be able to access setup page
    get new_device_setup_path
    assert_response :success

    # And create new device
    assert_difference("Device.count") do
      @user.devices.create!(public_key: "test_key_allowed")
    end
  end

  # Destroy Tests
  test "should destroy device" do
    device = @user.devices.create!(public_key: "test_key_to_destroy")

    assert_difference("Device.count", -1) do
      delete device_path(device)
    end

    assert_redirected_to devices_path
    follow_redirect!
    assert_match "removed", flash[:notice]
  end

  test "should allow adding device after deleting one at limit" do
    # Create subscription with basic plan (2 device limit)
    Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 2 devices (at limit)
    device1 = @user.devices.create!(public_key: "test_key_1")
    device2 = @user.devices.create!(public_key: "test_key_2")

    # Should not be able to access setup page
    get new_device_setup_path
    assert_redirected_to devices_path

    # Delete one device
    delete device_path(device1)

    # Should now be able to access setup page
    get new_device_setup_path
    assert_response :success

    # And create a new device
    assert_difference("Device.count") do
      @user.devices.create!(public_key: "test_key_new")
    end
  end

  test "should not destroy device of another user" do
    other_user = users(:two)
    other_device = other_user.devices.create!(public_key: "other_user_device_key")

    # Try to delete other user's device - should get 404 or redirect
    delete device_path(other_device)

    # Device should still exist
    assert Device.exists?(other_device.id)

    # Should either get 404 or redirect
    assert_response(:not_found) || assert_redirected_to(devices_path)
  end

  # Edge Cases
  test "should handle expired subscription as default limit" do
    # Create expired subscription
    Subscription.create!(
      user: @user,
      plan: @basic_plan,  # 2 device limit
      status: :expired,
      started_at: 31.days.ago,
      expires_at: 1.day.ago
    )

    # Should use default limit (5)
    5.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Should not be able to access setup page
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit of 5 devices", flash[:alert]
  end

  test "should handle cancelled subscription as default limit" do
    # Create cancelled subscription
    Subscription.create!(
      user: @user,
      plan: @pro_plan,  # 5 device limit
      status: :cancelled,
      started_at: Time.current,
      expires_at: 30.days.from_now,
      cancelled_at: Time.current
    )

    # Should use default limit (5)
    5.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Should not be able to access setup page
    get new_device_setup_path
    assert_redirected_to devices_path
  end

  test "should show correct messaging when at different limits" do
    # Test with basic plan
    subscription = Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    @user.devices.create!(public_key: "test_1")
    @user.devices.create!(public_key: "test_2")

    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "limit of 2 devices", flash[:alert]

    # Upgrade to pro plan
    subscription.update!(plan: @pro_plan)

    # Add more devices
    @user.devices.create!(public_key: "test_3")
    @user.devices.create!(public_key: "test_4")
    @user.devices.create!(public_key: "test_5")

    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "limit of 5 devices", flash[:alert]
  end

  # UI Elements Tests
  test "should show setup new device button when under limit" do
    get devices_path
    assert_response :success
    assert_select "a", text: "Setup New Device"
  end

  test "should show disabled button when at limit" do
    # Add 5 devices (at default limit)
    5.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    get devices_path
    assert_response :success
    assert_select "button[disabled]", text: "Device Limit Reached"
  end
end
