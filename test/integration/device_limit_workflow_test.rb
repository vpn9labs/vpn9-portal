require "test_helper"

class DeviceLimitWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    # Create user and capture the passphrase
    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.regenerate_passphrase!

    # Create test plans
    @free_plan = plans(:free_1)

    @basic_plan = plans(:basic_3)

    @pro_plan = plans(:pro_10)

    @unlimited_plan = plans(:unlimited_100)
  end

  test "complete device management workflow with plan upgrades" do
    # Sign in
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Check initial state (no subscription, default limit)
    get devices_path
    assert_response :success
    assert_match "0 of 5 devices used", response.body

    # Add devices up to default limit
    5.times do |i|
      # Use the new device setup flow
      @user.devices.create!(public_key: "default_key_#{i}")
    end

    # Verify we're at limit
    get devices_path
    assert_match "5 of 5 devices used", response.body

    # Try to add one more - should fail
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit", flash[:alert]

    # Subscribe to basic plan (3 device limit - lower than current)
    subscription = Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Should show over limit
    get devices_path
    assert_match "5 of 3 devices used", response.body

    # Can't add more devices
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit of 3 devices", flash[:alert]

    # Remove 3 devices to get under limit
    devices_to_remove = @user.devices.limit(3)
    devices_to_remove.each do |device|
      delete device_path(device)
      assert_redirected_to devices_path
    end

    # Should now be at limit
    get devices_path
    assert_match "2 of 3 devices used", response.body

    # Can add one more
    @user.devices.create!(public_key: "new_device_key")
    get devices_path
    assert_match "3 of 3 devices used", response.body

    # Now at limit again
    get devices_path
    assert_match "3 of 3 devices used", response.body

    # Upgrade to Pro plan
    subscription.update!(plan: @pro_plan)

    get devices_path
    assert_match "3 of 10 devices used", response.body

    # Can add more devices now
    5.times do |i|
      @user.devices.create!(public_key: "pro_key_#{i}")
    end

    get devices_path
    assert_match "8 of 10 devices used", response.body
  end

  test "device limit enforcement across subscription lifecycle" do
    # Sign in
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Start with free plan (1 device limit)
    subscription = Subscription.create!(
      user: @user,
      plan: @free_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add one device
    @user.devices.create!(public_key: "free_device_key")

    # Can't add second device
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit of 1 devices", flash[:alert]

    # Expire the subscription
    subscription.update!(
      status: :expired
    )

    # Should now have default limit (5)
    get devices_path
    assert_match "1 of 5 devices used", response.body

    # Can add more devices
    3.times do |i|
      @user.devices.create!(public_key: "default_key_#{i}")
    end

    get devices_path
    assert_match "4 of 5 devices used", response.body

    # Get unlimited plan
    new_subscription = Subscription.create!(
      user: @user,
      plan: @unlimited_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    get devices_path
    assert_match "4 of 100 devices used", response.body

    # Can add many more devices
    20.times do |i|
      @user.devices.create!(public_key: "unlimited_key_#{i}")
    end

    get devices_path
    assert_match "24 of 100 devices used", response.body
  end

  test "device limit messaging and UI elements" do
    # Sign in
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Create subscription with basic plan
    Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Check devices page shows limit info
    get devices_path
    assert_response :success
    assert_select "p", text: /0 of 3 devices used/
    assert_select "a", text: "Setup New Device"

    # Add devices
    2.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    get devices_path
    assert_select "p", text: /2 of 3 devices used/
    assert_select "a", text: "Setup New Device"

    # Add one more to reach limit
    @user.devices.create!(public_key: "test_key_3")

    get devices_path
    assert_select "p", text: /3 of 3 devices used/
    # Should show disabled button when at limit
    assert_select "button[disabled]", text: "Device Limit Reached"
  end

  test "concurrent device operations respect limits" do
    # Sign in
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Create subscription with basic plan (3 device limit)
    Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 2 devices
    2.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Open two browser sessions (simulated)
    # Both try to add a device when only one slot remains

    # First request should succeed
    @user.devices.create!(public_key: "concurrent_key_1")
    assert_equal 3, @user.devices.count

    # Second request should fail (now at limit)
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit", flash[:alert]

    # Verify final state
    assert_equal 3, @user.devices.count
    get devices_path
    assert_match "3 of 3 devices used", response.body
  end

  test "device limit changes immediately reflect in UI" do
    # Sign in
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Start with basic plan
    subscription = Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add 3 devices (at limit)
    3.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Check current state
    get devices_path
    assert_match "3 of 3 devices used", response.body

    # Admin changes plan to pro (happens in another session/process)
    subscription.update!(plan: @pro_plan)

    # User refreshes page - should immediately see new limit
    get devices_path
    assert_match "3 of 10 devices used", response.body

    # Can now add more devices
    get new_device_setup_path
    assert_response :success
    assert_select "h3", "Setup New Device"

    @user.devices.create!(public_key: "new_pro_device")
    get devices_path
    assert_match "4 of 10 devices used", response.body
  end

  test "dashboard shows correct device count and limits" do
    # Sign in
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Check dashboard without subscription
    get root_path
    assert_response :success
    assert_select "span", text: "0"

    # Add devices
    3.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    get root_path
    assert_select "span", text: "3"

    # Add subscription with limit
    Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Dashboard should still show count (not limit)
    get root_path
    assert_select "span", text: "3"
  end

  test "error handling for device limit edge cases" do
    # Sign in
    post session_path, params: {
      passphrase: "#{@passphrase}:password",
      email_address: @user.email_address
    }

    # Create subscription
    subscription = Subscription.create!(
      user: @user,
      plan: @basic_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Add devices to limit
    3.times do |i|
      @user.devices.create!(public_key: "test_key_#{i}")
    end

    # Try to add device at limit - should redirect due to limit check
    get new_device_setup_path
    assert_redirected_to devices_path
    follow_redirect!
    assert_match "You have reached your device limit", flash[:alert]

    # Delete a device
    delete device_path(@user.devices.first)

    # Now can access the setup page
    get new_device_setup_path
    assert_response :success

    # Verify device count didn't change
    assert_equal 2, @user.devices.count
  end
end
