require "test_helper"

class Admin::DevicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Create admin
    @admin = Admin.create!(
      email: "admin@example.com",
      password: "admin_password"
    )

    # Create regular user with devices
    @user = User.create!(email_address: "user@example.com", password: "password")
    @device = @user.devices.create!(public_key: "test_public_key_123", name: "test-device")

    # Sign in as admin
    post admin_session_path, params: {
      email: @admin.email,
      password: "admin_password"
    }
  end

  test "should remove user device from admin panel" do
    assert_difference("Device.count", -1) do
      delete admin_user_device_path(@user, @device)
    end

    assert_redirected_to admin_user_path(@user)
    follow_redirect!
    assert_match "Device 'test-device' was successfully removed", flash[:notice]
  end

  test "should handle non-existent device" do
    # Try to delete a non-existent device
    delete admin_user_device_path(@user, id: "999999")

    # Should get a 404 response
    assert_response :not_found
  end

  test "should redirect to login if not authenticated" do
    delete admin_session_path  # Sign out

    delete admin_user_device_path(@user, @device)
    assert_redirected_to new_admin_session_path
  end
end
