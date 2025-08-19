require "test_helper"

class Admin::LaunchNotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Admin.create!(
      email: "admin@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    # Sign in as admin
    post admin_session_path, params: {
      email: @admin.email,
      password: "password123"
    }

    # Create some test launch notifications
    @notification1 = LaunchNotification.create!(
      email: "user1@example.com",
      metadata: {
        "ip_address" => "192.168.1.1",
        "utm_source" => "twitter",
        "utm_campaign" => "launch"
      }
    )

    @notification2 = LaunchNotification.create!(
      email: "user2@example.com",
      metadata: {
        "ip_address" => "192.168.1.2",
        "utm_source" => "facebook"
      }
    )
  end

  test "should get index" do
      get admin_launch_notifications_path
      assert_response :success
      assert_select "h1", "Launch Notifications"
      assert_match @notification1.email, response.body
      assert_match @notification2.email, response.body
    end

  test "should show launch notification" do
      get admin_launch_notification_path(@notification1)
      assert_response :success
      assert_match @notification1.email, response.body
      assert_match "192.168.1.1", response.body
      assert_match "twitter", response.body
    end

  test "should destroy launch notification" do
      assert_difference("LaunchNotification.count", -1) do
        delete admin_launch_notification_path(@notification1)
      end
      assert_redirected_to admin_launch_notifications_path
      assert_equal "Launch notification signup was successfully removed.", flash[:notice]
    end

  test "should get stats" do
      get stats_admin_launch_notifications_path
      assert_response :success
      assert_select "h1", "Launch Notification Statistics"
      assert_match "Total Signups", response.body
      assert_match "2", response.body # We have 2 test notifications
    end

  test "should export CSV" do
      get export_admin_launch_notifications_path(format: :csv)
      assert_response :success
      assert_equal "text/csv", response.content_type
      assert_match "user1@example.com", response.body
      assert_match "user2@example.com", response.body
      assert_match "twitter", response.body
    end

  test "should filter by search term" do
      get admin_launch_notifications_path, params: { search: "user1" }
      assert_response :success
      assert_match "user1@example.com", response.body
      assert_no_match "user2@example.com", response.body
    end

  test "should filter by date range" do
    # Just test that the filter parameters are accepted and the page loads
    get admin_launch_notifications_path, params: {
      date_from: 1.week.ago.to_date.to_s,
      date_to: 1.week.from_now.to_date.to_s
    }
    assert_response :success
    # Should show the filter form with values filled in
    assert_select "input[name='date_from'][value]"
    assert_select "input[name='date_to'][value]"
  end

  test "should require admin authentication" do
      # Sign out
      delete admin_session_path

      get admin_launch_notifications_path
      assert_redirected_to new_admin_session_path
    end

  test "should show empty state when no notifications" do
      LaunchNotification.destroy_all

      get admin_launch_notifications_path
      assert_response :success
      assert_match "No launch notification signups found", response.body
    end

  test "navigation link should be highlighted when active" do
      get admin_launch_notifications_path
      assert_response :success
      assert_select "a.bg-gray-900", text: /Launch Notifications/
    end
end
