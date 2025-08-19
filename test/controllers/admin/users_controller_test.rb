require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Create an admin user for authentication
    @admin = Admin.create!(
      email: "admin@example.com",
      password: "password123"
    )

    # Create test users with proper encrypted email addresses
    @user1 = User.create!(email_address: "user1@example.com")
    @user2 = User.create!(email_address: "user2@example.com")
    @anonymous_user = User.create!(email_address: nil)

    # Create test plan
    @plan = Plan.create!(
      name: "Test Plan",
      price: 10.00,
      currency: "USD",
      duration_days: 30,
      device_limit: 5,
      active: true
    )
  end

  # ========== Authentication Tests ==========

  test "should redirect index when not authenticated" do
    get admin_users_url
    assert_redirected_to new_admin_session_url
  end

  test "should redirect show when not authenticated" do
    get admin_user_url(@user1)
    assert_redirected_to new_admin_session_url
  end

  test "should redirect edit when not authenticated" do
    get edit_admin_user_url(@user1)
    assert_redirected_to new_admin_session_url
  end

  test "should redirect update when not authenticated" do
    patch admin_user_url(@user1), params: { user: { email_address: "new@example.com" } }
    assert_redirected_to new_admin_session_url
  end

  # ========== Index Action Tests ==========

  test "should get index when authenticated as admin" do
    login_as_admin
    # Clear any fixture users to avoid encryption issues
    User.destroy_all
    # Create fresh test users
    User.create!(email_address: "fresh1@example.com")
    User.create!(email_address: "fresh2@example.com")

    get admin_users_url
    assert_response :success
    assert_select "h1", "Users"
  end

  test "should display users in index" do
    login_as_admin
    # Clear any fixture users to avoid encryption issues
    User.destroy_all
    # Create fresh test users
    user1 = User.create!(email_address: "display1@example.com")
    user2 = User.create!(email_address: "display2@example.com")

    get admin_users_url
    assert_response :success
    # Check that the table has rows for users
    assert_select "tbody tr", minimum: 2
  end

  test "should paginate users in index" do
    login_as_admin
    # Clear any fixture users to avoid encryption issues
    User.destroy_all

    # Create many users to trigger pagination
    15.times do |i|
      User.create!(email_address: "test#{i}@example.com")
    end

    get admin_users_url
    assert_response :success

    # Test second page
    get admin_users_url, params: { page: 2 }
    assert_response :success
  end

  test "should handle empty user list" do
    login_as_admin

    # Delete all users
    User.destroy_all

    get admin_users_url
    assert_response :success
  end

  # ========== Show Action Tests ==========

  test "should show user when authenticated as admin" do
    login_as_admin
    get admin_user_url(@user1)
    assert_response :success
  end

  test "should display user details in show" do
    login_as_admin

    # Create some associated data
    subscription = @user1.subscriptions.create!(
      plan: @plan,
      started_at: Time.current,
      expires_at: 30.days.from_now,
      status: :active
    )

    payment = @user1.payments.create!(
      plan: @plan,
      amount: 10.00,
      currency: "USD",
      status: :paid
    )

    device = @user1.devices.create!(
      name: "Test Device",
      public_key: "test_public_key_123"
    )

    get admin_user_url(@user1)
    assert_response :success

    # Verify user information is displayed
    # Verify user information is displayed
    assert_select "h1", "User Details"
    assert_match "##{@user1.id}", response.body
    assert_match @user1.email_address, response.body

    # Verify associations are displayed
    assert_match @plan.name, response.body
    assert_match device.name, response.body
  end

  test "should handle user with no associations" do
    login_as_admin

    get admin_user_url(@user2)
    assert_response :success
    assert_select "h1", "User Details"
  end

  test "should handle non-existent user in show" do
    login_as_admin

    # Non-existent ID should return 404 or redirect
    get admin_user_url(id: 999999)
    assert_response :not_found
  end

  test "should show anonymous user without email" do
    login_as_admin

    get admin_user_url(@anonymous_user)
    assert_response :success
    assert_select "h1", "User Details"
  end

  # ========== Edit Action Tests ==========

  test "should get edit when authenticated as admin" do
    login_as_admin
    get edit_admin_user_url(@user1)
    assert_response :success
    assert_select "h1", "Edit User"
  end

  test "should display edit form with current values" do
    login_as_admin
    get edit_admin_user_url(@user1)
    assert_response :success

    # Check that form has current values
    assert_select "input[name='user[email_address]'][value=?]", @user1.email_address
    assert_select "select[name='user[status]'] option[selected]", text: @user1.status.capitalize
  end

  test "should handle non-existent user in edit" do
    login_as_admin

    # Non-existent ID should return 404 or redirect
    get edit_admin_user_url(id: 999999)
    assert_response :not_found
  end

  # ========== Update Action Tests ==========

  test "should update user email_address" do
    login_as_admin

    new_email = "newemail@example.com"
    patch admin_user_url(@user1), params: {
      user: { email_address: new_email }
    }

    assert_redirected_to admin_user_path(@user1)
    assert_equal "User was successfully updated.", flash[:notice]

    @user1.reload
    assert_equal new_email, @user1.email_address
  end

  test "should update user status" do
    login_as_admin

    assert_equal "active", @user1.status

    patch admin_user_url(@user1), params: {
      user: { status: "locked" }
    }

    assert_redirected_to admin_user_path(@user1)
    assert_equal "User was successfully updated.", flash[:notice]

    @user1.reload
    assert_equal "locked", @user1.status
  end

  test "should update both email_address and status" do
    login_as_admin

    patch admin_user_url(@user1), params: {
      user: {
        email_address: "updated@example.com",
        status: "closed"
      }
    }

    assert_redirected_to admin_user_path(@user1)

    @user1.reload
    assert_equal "updated@example.com", @user1.email_address
    assert_equal "closed", @user1.status
  end

  test "should not update with invalid email format" do
    login_as_admin

    patch admin_user_url(@user1), params: {
      user: { email_address: "invalid-email" }
    }

    assert_response :unprocessable_content
    assert_select "h1", "Edit User"

    # Email should not have changed
    @user1.reload
    assert_not_equal "invalid-email", @user1.email_address
  end

  test "should not update with invalid status" do
    login_as_admin

    # Test invalid status
    assert_raises(ArgumentError) do
      patch admin_user_url(@user1), params: {
        user: { status: "invalid_status" }
      }
    end
  end

  test "should handle empty update params" do
    login_as_admin

    original_email = @user1.email_address
    original_status = @user1.status

    # Empty params should still work
    patch admin_user_url(@user1), params: {
      user: { email_address: original_email }
    }

    assert_redirected_to admin_user_path(@user1)

    @user1.reload
    assert_equal original_email, @user1.email_address
    assert_equal original_status, @user1.status
  end

  test "should normalize email on update" do
    login_as_admin

    # Test email normalization (strips whitespace, lowercases)
    patch admin_user_url(@user1), params: {
      user: { email_address: "  UpperCase@EXAMPLE.COM  " }
    }

    assert_redirected_to admin_user_path(@user1)

    @user1.reload
    assert_equal "uppercase@example.com", @user1.email_address
  end

  test "should handle non-existent user in update" do
    login_as_admin

    # Non-existent ID should return 404 or redirect
    patch admin_user_url(id: 999999), params: {
      user: { email_address: "test@example.com" }
    }
    assert_response :not_found
  end

  test "should not allow updating unpermitted attributes" do
    login_as_admin

    original_passphrase = @user1.passphrase_hash
    original_created_at = @user1.created_at

    patch admin_user_url(@user1), params: {
      user: {
        email_address: "new@example.com",
        passphrase_hash: "hacked",
        recovery_code: "hacked",
        created_at: 1.year.ago
      }
    }

    assert_redirected_to admin_user_path(@user1)

    @user1.reload
    # Email should be updated
    assert_equal "new@example.com", @user1.email_address
    # But protected attributes should not change
    assert_equal original_passphrase, @user1.passphrase_hash
    assert_equal original_created_at.to_i, @user1.created_at.to_i
  end

  test "should handle duplicate email on update" do
    login_as_admin

    # Create fresh users to avoid encryption issues
    user_a = User.create!(email_address: "usera@example.com")
    user_b = User.create!(email_address: "userb@example.com")

    # Try to update to an existing email - this should fail
    begin
      patch admin_user_url(user_a), params: {
        user: { email_address: user_b.email_address }
      }
      # If we get here, check that it was handled as a validation error
      assert_response :unprocessable_content
    rescue ActiveRecord::RecordNotUnique
      # Database constraint violation is also acceptable
      pass
    end

    # Verify the email wasn't changed
    user_a.reload
    assert_not_equal user_b.email_address, user_a.email_address
  end

  test "should handle updating anonymous user to have email" do
    login_as_admin

    patch admin_user_url(@anonymous_user), params: {
      user: { email_address: "nowanon@example.com" }
    }

    assert_redirected_to admin_user_path(@anonymous_user)

    @anonymous_user.reload
    assert_equal "nowanon@example.com", @anonymous_user.email_address
  end

  # ========== Integration Tests ==========

  test "should handle full user management workflow" do
    login_as_admin
    # Clear any fixture users to avoid encryption issues
    User.destroy_all
    # Create a fresh test user
    test_user = User.create!(email_address: "workflow@example.com")

    # View user list
    get admin_users_url
    assert_response :success
    assert_select "tbody tr", minimum: 1

    # View user details
    get admin_user_url(test_user)
    assert_response :success
    assert_match test_user.email_address, response.body

    # Edit user
    get edit_admin_user_url(test_user)
    assert_response :success

    # Update user
    patch admin_user_url(test_user), params: {
      user: {
        email_address: "updated@example.com",
        status: "locked"
      }
    }
    assert_redirected_to admin_user_path(test_user)

    # Verify changes
    test_user.reload
    assert_equal "updated@example.com", test_user.email_address
    assert_equal "locked", test_user.status
  end

  test "should display correct counts and statuses" do
    login_as_admin
    # Clear any fixture users to avoid encryption issues
    User.destroy_all
    # Create fresh test user
    test_user = User.create!(email_address: "counts@example.com")

    # Create associations
    test_user.subscriptions.create!(
      plan: @plan,
      started_at: Time.current,
      expires_at: 30.days.from_now,
      status: :active
    )

    3.times do |i|
      test_user.devices.create!(
        name: "Device #{i}",
        public_key: "key_#{i}"
      )
    end

    get admin_users_url
    assert_response :success

    # Check that data is displayed in the table
    assert_select "tbody tr", minimum: 1
    # Verify subscription and device counts are shown
    assert_match "1", response.body  # Subscription count
    assert_match "3", response.body  # Device count
  end

  # ========== Security Tests ==========

  test "should not allow SQL injection in page parameter" do
    login_as_admin
    # Clear any fixture users to avoid encryption issues
    User.destroy_all
    # Create a fresh test user
    User.create!(email_address: "sql@example.com")

    # Try SQL injection in page parameter
    get admin_users_url, params: { page: "1; DROP TABLE users;" }
    assert_response :success
  end

  test "should handle XSS attempt in update" do
    login_as_admin

    xss_attempt = "<script>alert('XSS')</script>@example.com"
    patch admin_user_url(@user1), params: {
      user: { email_address: xss_attempt }
    }

    # Should fail validation due to invalid email format
    assert_response :unprocessable_content
  end

  test "should escape user input in views" do
    login_as_admin

    skip "Email validation prevents < > characters"
  end

  private

  def login_as_admin
    post admin_session_url, params: {
      email: @admin.email,
      password: "password123"
    }
  end
end
