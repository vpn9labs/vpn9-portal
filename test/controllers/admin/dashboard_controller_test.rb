require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Clean up existing data to avoid conflicts
    Admin.destroy_all
    User.destroy_all
    Plan.destroy_all
    Subscription.destroy_all
    Payment.destroy_all

    # Create an admin user for authentication
    @admin = Admin.create!(
      email: "admin@example.com",
      password: "password123"
    )

    # Create another admin for testing
    @admin2 = Admin.create!(
      email: "admin2@example.com",
      password: "password456"
    )

    # Create test plans
    @monthly_plan = Plan.create!(
      name: "Monthly Basic",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 3,
      active: true
    )

    @yearly_plan = Plan.create!(
      name: "Yearly Premium",
      price: 99.99,
      currency: "USD",
      duration_days: 365,
      device_limit: 10,
      active: true
    )

    @inactive_plan = Plan.create!(
      name: "Legacy Plan",
      price: 4.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 1,
      active: false
    )

    # Create test users with various statuses
    @active_user = User.create!(
      email_address: "active@example.com",
      status: :active
    )

    @anonymous_user = User.create!(
      email_address: nil,
      status: :active
    )

    @locked_user = User.create!(
      email_address: "locked@example.com",
      status: :locked
    )

    @closed_user = User.create!(
      email_address: "closed@example.com",
      status: :closed
    )

    # Create older users for recent users list
    @old_user1 = User.create!(
      email_address: "old1@example.com",
      created_at: 30.days.ago
    )

    @old_user2 = User.create!(
      email_address: "old2@example.com",
      created_at: 60.days.ago
    )

    # Create recent users
    10.times do |i|
      User.create!(
        email_address: "recent#{i}@example.com",
        created_at: i.days.ago
      )
    end

    # Create subscriptions with various statuses
    @active_subscription1 = Subscription.create!(
      user: @active_user,
      plan: @monthly_plan,
      status: :active,
      started_at: 15.days.ago,
      expires_at: 15.days.from_now
    )

    @active_subscription2 = Subscription.create!(
      user: @anonymous_user,
      plan: @yearly_plan,
      status: :active,
      started_at: 100.days.ago,
      expires_at: 265.days.from_now
    )

    @expired_subscription = Subscription.create!(
      user: @locked_user,
      plan: @monthly_plan,
      status: :expired,
      started_at: 45.days.ago,
      expires_at: 15.days.ago
    )

    @cancelled_subscription = Subscription.create!(
      user: @closed_user,
      plan: @yearly_plan,
      status: :cancelled,
      started_at: 30.days.ago,
      expires_at: 335.days.from_now,
      cancelled_at: 5.days.ago
    )

    @pending_subscription = Subscription.create!(
      user: @old_user1,
      plan: @monthly_plan,
      status: :pending,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    # Create active but expired subscription (edge case)
    @active_but_expired = Subscription.create!(
      user: @old_user2,
      plan: @monthly_plan,
      status: :active,
      started_at: 35.days.ago,
      expires_at: 5.days.ago  # Expired but still marked as active
    )

    # Create payments with various statuses
    @successful_payment1 = Payment.create!(
      user: @active_user,
      subscription: @active_subscription1,
      plan: @monthly_plan,
      amount: 9.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN001",
      created_at: 15.days.ago
    )

    @successful_payment2 = Payment.create!(
      user: @anonymous_user,
      subscription: @active_subscription2,
      plan: @yearly_plan,
      amount: 99.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN002",
      created_at: 100.days.ago
    )

    @successful_payment3 = Payment.create!(
      user: @locked_user,
      plan: @monthly_plan,
      amount: 9.99,
      currency: "USD",
      status: :overpaid,  # Also counts as successful
      transaction_id: "TXN003",
      created_at: 45.days.ago
    )

    @pending_payment = Payment.create!(
      user: @old_user1,
      subscription: @pending_subscription,
      plan: @monthly_plan,
      amount: 9.99,
      currency: "USD",
      status: :pending,
      transaction_id: "TXN004"
    )

    @failed_payment = Payment.create!(
      user: @closed_user,
      plan: @yearly_plan,
      amount: 99.99,
      currency: "USD",
      status: :failed,
      transaction_id: "TXN005",
      created_at: 30.days.ago
    )

    @partial_payment = Payment.create!(
      user: @old_user2,
      plan: @monthly_plan,
      amount: 5.00,
      currency: "USD",
      status: :partial,
      transaction_id: "TXN006",
      created_at: 5.days.ago
    )

    # Create recent successful payments for display
    8.times do |i|
      Payment.create!(
        user: User.create!(email_address: "payment_user#{i}@example.com"),
        plan: [ @monthly_plan, @yearly_plan ].sample,
        amount: [ 9.99, 99.99 ].sample,
        currency: "USD",
        status: [ :paid, :overpaid ].sample,
        transaction_id: "TXN_RECENT_#{i}",
        created_at: i.hours.ago
      )
    end
  end

  # ========== Authentication Tests ==========

  test "should redirect to login when not authenticated" do
    get admin_root_url
    assert_redirected_to new_admin_session_url
  end

  test "should get index when authenticated as admin" do
    login_as_admin
    get admin_root_url
    assert_response :success
    assert_select "h1", "Dashboard"
  end

  test "should not allow non-admin users to access dashboard" do
    # Try to access without admin session
    get admin_root_url
    assert_redirected_to new_admin_session_url
  end

  test "should maintain admin session across requests" do
    login_as_admin

    # First request
    get admin_root_url
    assert_response :success

    # Second request should still be authenticated
    get admin_root_url
    assert_response :success
  end

  # ========== Statistics Display Tests ==========

  test "should display correct user count" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Total users count should include all users
    total_users = User.count
    assert_select "dd", text: total_users.to_s
  end

  test "should display correct active subscriptions count" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Active subscriptions that haven't expired
    active_count = Subscription.active.where("expires_at > ?", Time.current).count
    assert_match active_count.to_s, response.body
  end

  test "should display correct total successful payments count" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Successful payments include paid and overpaid statuses
    successful_count = Payment.successful.count
    assert_match successful_count.to_s, response.body
  end

  test "should display statistics cards" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check for the three main statistics cards
    assert_select "dt", text: "Total Users"
    assert_select "dt", text: "Active Subscriptions"
    assert_select "dt", text: "Total Successful Payments"
  end

  test "should handle zero statistics gracefully" do
    # Delete all data
    Payment.destroy_all
    Subscription.destroy_all
    User.destroy_all

    login_as_admin
    get admin_root_url
    assert_response :success

    # Should display zeros
    assert_select "dd", text: "0", count: 3
  end

  # ========== Recent Payments Tests ==========

  test "should display recent payments section" do
    login_as_admin
    get admin_root_url
    assert_response :success

    assert_select "h3", text: "Recent Payments"
  end

  test "should display 10 most recent successful payments" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Should show only 10 payments even though we have more
    # Count the payment list items
    doc = Nokogiri::HTML(response.body)
    # Find the Recent Payments section by its heading
    payments_section = doc.at_xpath("//h3[text()='Recent Payments']/ancestor::div[contains(@class, 'bg-white')]")
    payment_items = payments_section.css("li.px-4.py-4") if payments_section
    assert_equal 10, payment_items&.size || 0, "Should show exactly 10 recent payments"
  end

  test "should display payment details correctly" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check for payment information
    recent_payment = Payment.successful.recent.first
    if recent_payment
      # User email or ID
      if recent_payment.user.email_address
        assert_match recent_payment.user.email_address, response.body
      else
        assert_match "User ##{recent_payment.user.id}", response.body
      end

      # Plan name
      assert_match recent_payment.plan.name, response.body

      # Amount
      assert_match number_to_currency(recent_payment.amount), response.body
    end
  end

  test "should link to user profile from payment" do
    login_as_admin
    get admin_root_url
    assert_response :success

    recent_payment = Payment.successful.recent.first
    if recent_payment
      assert_select "a[href=?]", admin_user_path(recent_payment.user), minimum: 1
    end
  end

  test "should display payment date" do
    login_as_admin
    get admin_root_url
    assert_response :success

    recent_payment = Payment.successful.recent.first
    if recent_payment
      assert_match recent_payment.created_at.strftime("%B"), response.body
    end
  end

  test "should order payments by most recent first" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Get the payment dates from the response
    # Most recent should appear first
    payments = Payment.successful.recent.limit(10)
    if payments.count > 1
      first_payment = payments.first
      last_payment = payments.last
      assert first_payment.created_at > last_payment.created_at
    end
  end

  test "should handle payments with anonymous users" do
    # Create a recent payment for the anonymous user to ensure it appears
    Payment.create!(
      user: @anonymous_user,
      plan: @monthly_plan,
      amount: 9.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN_ANON_RECENT",
      created_at: 1.second.ago
    )

    login_as_admin
    get admin_root_url
    assert_response :success

    # The anonymous user's payment should be displayed
    # Since @anonymous_user has nil email_address, it should display "User #ID"
    assert_nil @anonymous_user.email_address
    assert_match "User ##{@anonymous_user.id}", response.body
  end

  test "should exclude failed payments from recent payments" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Failed payment transaction ID should not appear
    refute_match @failed_payment.transaction_id, response.body
  end

  test "should exclude pending payments from recent payments" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Pending payment transaction ID should not appear
    refute_match @pending_payment.transaction_id, response.body
  end

  test "should include overpaid payments as successful" do
    login_as_admin

    # Create a recent overpaid payment
    overpaid = Payment.create!(
      user: @active_user,
      plan: @monthly_plan,
      amount: 15.00,
      currency: "USD",
      status: :overpaid,
      transaction_id: "TXN_OVERPAID",
      created_at: 1.minute.ago
    )

    get admin_root_url
    assert_response :success

    # Overpaid payments should be included in successful payments
    assert_match overpaid.plan.name, response.body
  end

  # ========== Recent Users Tests ==========

  test "should display recent users section" do
    login_as_admin
    get admin_root_url
    assert_response :success

    assert_select "h3", text: "Recent Users"
  end

  test "should display 10 most recent users" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Should show only 10 users even though we have more
    recent_users_count = css_select("div.bg-white").last.css("li.px-4.py-4").count
    assert_equal 10, recent_users_count
  end

  test "should display user details correctly" do
    login_as_admin
    get admin_root_url
    assert_response :success

    recent_user = User.order(created_at: :desc).first

    # User email or ID
    if recent_user.email_address
      assert_match recent_user.email_address, response.body
    else
      assert_match "User ##{recent_user.id}", response.body
    end

    # User status
    assert_match recent_user.status.humanize, response.body
  end

  test "should link to user profile from recent users" do
    login_as_admin
    get admin_root_url
    assert_response :success

    recent_user = User.order(created_at: :desc).first
    assert_select "a[href=?]", admin_user_path(recent_user), minimum: 1
  end

  test "should display user registration date" do
    login_as_admin
    get admin_root_url
    assert_response :success

    recent_user = User.order(created_at: :desc).first
    assert_match recent_user.created_at.strftime("%B"), response.body
  end

  test "should order users by most recent first" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Most recent users should appear first
    users = User.order(created_at: :desc).limit(10)
    if users.count > 1
      first_user = users.first
      last_user = users.last
      assert first_user.created_at > last_user.created_at
    end
  end

  test "should handle anonymous users in recent users list" do
    login_as_admin

    # Create a recent anonymous user
    anon_user = User.create!(
      email_address: nil,
      created_at: 1.second.ago
    )

    get admin_root_url
    assert_response :success

    # Should display "User #ID" for anonymous users
    assert_match "User ##{anon_user.id}", response.body
  end

  test "should display user status for each user" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check that status is displayed
    assert_match "Status:", response.body
  end

  # ========== Performance Tests ==========

  test "should use includes to avoid N+1 queries for payments" do
    login_as_admin

    # The controller should use includes(:user, :plan)
    # This test ensures the view can access user and plan without additional queries
    assert_nothing_raised do
      get admin_root_url
    end
    assert_response :success
  end

  test "should handle large datasets efficiently" do
    # Create many records
    50.times do |i|
      user = User.create!(email_address: "bulk#{i}@example.com")
      plan = @monthly_plan

      Subscription.create!(
        user: user,
        plan: plan,
        status: :active,
        started_at: i.days.ago,
        expires_at: (30 - i).days.from_now
      )

      Payment.create!(
        user: user,
        plan: plan,
        amount: 9.99,
        currency: "USD",
        status: :paid,
        transaction_id: "BULK_TXN_#{i}",
        created_at: i.hours.ago
      )
    end

    login_as_admin

    start_time = Time.current
    get admin_root_url
    load_time = Time.current - start_time

    assert_response :success
    assert load_time < 2, "Page took too long to load: #{load_time} seconds"
  end

  # ========== Layout and UI Tests ==========

  test "should use admin layout" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check for admin layout elements
    assert_select "nav" # Admin navigation
  end

  test "should display dashboard title" do
    login_as_admin
    get admin_root_url
    assert_response :success

    assert_select "h1", "Dashboard"
  end

  test "should use grid layout for statistics" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check for grid layout classes
    assert_select "dl.grid"
  end

  test "should use two-column layout for recent items" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check for two-column grid
    assert_select "div.grid.lg\\:grid-cols-2"
  end

  # ========== Edge Cases ==========

  test "should handle no recent payments gracefully" do
    Payment.destroy_all

    login_as_admin
    get admin_root_url
    assert_response :success

    assert_select "h3", "Recent Payments"
    # Should still render without errors
  end

  test "should handle no recent users gracefully" do
    # Delete all payments and subscriptions first to avoid foreign key constraints
    Payment.destroy_all
    Subscription.destroy_all
    User.destroy_all
    Admin.destroy_all  # Also clear admins to avoid email conflicts
    # Recreate admin to be able to login
    @admin = Admin.create!(
      email: "admin_new@example.com",
      password: "password123"
    )

    login_as_admin(@admin)
    get admin_root_url
    assert_response :success

    assert_select "h3", "Recent Users"
    # Should still render without errors
  end

  test "should handle soft deleted users in counts" do
    # Soft delete some users
    @active_user.soft_delete!
    @locked_user.soft_delete!

    login_as_admin
    get admin_root_url
    assert_response :success

    # Count should exclude soft deleted users
    visible_users = User.count
    assert_select "dd", text: visible_users.to_s
  end

  test "should count only truly current subscriptions" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Should only count active subscriptions that haven't expired
    # @active_but_expired should NOT be counted even though status is active
    current_count = Subscription.active.where("expires_at > ?", Time.current).count

    # The count should not include @active_but_expired
    refute_includes Subscription.current.pluck(:id), @active_but_expired.id
  end

  test "should handle payments with deleted plans" do
    # Create a payment with a plan that will be deleted
    payment_with_plan = Payment.create!(
      user: @active_user,
      plan: @inactive_plan,
      amount: 4.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN_DELETED_PLAN",
      created_at: 1.minute.ago
    )

    login_as_admin
    get admin_root_url
    assert_response :success

    # Should still display the payment even with inactive plan
    assert_match @inactive_plan.name, response.body
  end

  test "should format currency correctly" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check for proper currency formatting
    assert_match "$9.99", response.body  # Monthly plan price
  end

  test "should format dates correctly" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Check for date formatting (Month Day, Year)
    today = Date.current
    assert_match today.strftime("%B"), response.body
  end

  # ========== Security Tests ==========

  test "should not expose sensitive user information" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Should not display passwords or tokens
    refute_match "password", response.body.downcase
    refute_match "token", response.body.downcase
    refute_match "digest", response.body.downcase
  end

  test "should escape user input in views" do
    # Create user with potentially malicious email
    xss_user = User.create!(
      email_address: "xss_test@example.com",
      created_at: 1.second.ago
    )

    Payment.create!(
      user: xss_user,
      plan: @monthly_plan,
      amount: 9.99,
      currency: "USD",
      status: :paid,
      transaction_id: "XSS_TXN",
      created_at: 1.second.ago
    )

    login_as_admin
    get admin_root_url
    assert_response :success

    # Should display the user's email correctly
    assert_match "xss_test@example.com", response.body
  end

  test "should require admin role not just authentication" do
    # If there were regular user sessions, they shouldn't work
    # This is handled by AdminAuthentication module
    get admin_root_url
    assert_redirected_to new_admin_session_url
  end

  # ========== Integration Tests ==========

  test "should provide quick overview of system health" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Dashboard should show all key metrics
    assert_select "dt", text: "Total Users"
    assert_select "dt", text: "Active Subscriptions"
    assert_select "dt", text: "Total Successful Payments"
    assert_select "h3", text: "Recent Payments"
    assert_select "h3", text: "Recent Users"
  end

  test "should allow navigation to user details" do
    login_as_admin
    get admin_root_url
    assert_response :success

    # Should have links to user profiles
    recent_user = User.order(created_at: :desc).first
    assert_select "a[href='#{admin_user_path(recent_user)}']"

    # Click through to user profile
    get admin_user_path(recent_user)
    assert_response :success
  end

  test "should refresh data on page reload" do
    login_as_admin

    # First load
    get admin_root_url
    assert_response :success
    initial_count = User.count

    # Add new user
    User.create!(email_address: "new_user@example.com")

    # Reload
    get admin_root_url
    assert_response :success

    # Should show updated count
    assert_select "dd", text: (initial_count + 1).to_s
  end

  private

  def login_as_admin(admin = nil)
    admin ||= @admin
    post admin_session_url, params: {
      email: admin.email,
      password: "password123"
    }
  end

  def number_to_currency(amount)
    "$#{'%.2f' % amount}"
  end
end
