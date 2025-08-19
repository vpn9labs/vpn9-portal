require "test_helper"

class Affiliates::ProfileControllerTest < ActionDispatch::IntegrationTest
  setup do
    @affiliate = affiliates(:active_affiliate)
    @pending_affiliate = affiliates(:pending_affiliate)
  end

  def affiliate_login(affiliate = @affiliate)
    post login_affiliates_path, params: {
      email: affiliate.email,
      password: "password123"
    }
  end

  # Authentication tests
  test "should require authentication for show" do
    get affiliates_profile_path
    assert_redirected_to login_affiliates_path
  end

  test "should require authentication for edit" do
    get edit_affiliates_profile_path
    assert_redirected_to login_affiliates_path
  end

  test "should require authentication for update" do
    patch affiliates_profile_path, params: {
      affiliate: { name: "New Name" }
    }
    assert_redirected_to login_affiliates_path
  end

  test "should require authentication for update_password" do
    patch update_password_affiliates_profile_path, params: {
      current_password: "password123",
      affiliate: { password: "newpassword", password_confirmation: "newpassword" }
    }
    assert_redirected_to login_affiliates_path
  end

  # Show action tests
  test "should get show when authenticated" do
    affiliate_login
    get affiliates_profile_path
    assert_response :success
    assert_select "h2", text: /Profile Settings/
  end

  test "should display affiliate information on show" do
    affiliate_login
    get affiliates_profile_path
    assert_response :success

    # Check for key information display
    assert_select "dd", text: @affiliate.email
    assert_select "span", text: @affiliate.code
    assert_match @affiliate.commission_rate.to_s, response.body
  end

  test "should display status badge on show" do
    affiliate_login
    get affiliates_profile_path
    assert_response :success
    assert_select "span", text: /Active/
  end

  test "should display payment settings on show" do
    affiliate_login
    get affiliates_profile_path
    assert_response :success
    assert_match @affiliate.payout_currency.upcase, response.body
    assert_match @affiliate.payout_address, response.body
    assert_match @affiliate.minimum_payout_amount.to_s, response.body
  end

  test "should display edit profile link on show" do
    affiliate_login
    get affiliates_profile_path
    assert_response :success
    assert_select "a[href=?]", edit_affiliates_profile_path, text: /Edit Profile/
  end

  # Edit action tests
  test "should get edit when authenticated" do
    affiliate_login
    get edit_affiliates_profile_path
    assert_response :success
    assert_select "h2", text: /Edit Profile/
  end

  test "should display profile form on edit" do
    affiliate_login
    get edit_affiliates_profile_path
    assert_response :success

    # Check for form fields
    assert_select "input[name='affiliate[name]']"
    assert_select "input[name='affiliate[email]']"
    assert_select "input[name='affiliate[company_name]']"
    assert_select "input[name='affiliate[website]']"
    assert_select "input[name='affiliate[phone]']"
    assert_select "textarea[name='affiliate[promotional_methods]']"
  end

  test "should display password change form on edit" do
    affiliate_login
    get edit_affiliates_profile_path
    assert_response :success

    assert_select "input[name='current_password']"
    assert_select "input[name='affiliate[password]']"
    assert_select "input[name='affiliate[password_confirmation]']"
  end

  test "should display payment settings as read-only on edit" do
    affiliate_login
    get edit_affiliates_profile_path
    assert_response :success

    # Payment settings should be displayed but not editable
    assert_match @affiliate.payout_currency.upcase, response.body
    assert_match @affiliate.payout_address, response.body
    assert_match "contact support", response.body.downcase
  end

  # Update action tests
  test "should update profile with valid data" do
    affiliate_login

    patch affiliates_profile_path, params: {
      affiliate: {
        name: "Updated Name",
        email: "updated@example.com",
        company_name: "Updated Company",
        website: "https://updated.com",
        phone: "+1234567890"
      }
    }

    assert_redirected_to affiliates_profile_path
    follow_redirect!
    assert_match "Profile updated successfully", response.body

    @affiliate.reload
    assert_equal "Updated Name", @affiliate.name
    assert_equal "updated@example.com", @affiliate.email
    assert_equal "Updated Company", @affiliate.company_name
  end

  test "should update business information" do
    affiliate_login

    patch affiliates_profile_path, params: {
      affiliate: {
        address: "123 Main St",
        city: "New York",
        state: "NY",
        country: "USA",
        postal_code: "10001",
        tax_id: "TAX-123456"
      }
    }

    assert_redirected_to affiliates_profile_path
    @affiliate.reload
    assert_equal "123 Main St", @affiliate.address
    assert_equal "New York", @affiliate.city
    assert_equal "NY", @affiliate.state
  end

  test "should update marketing information" do
    affiliate_login

    patch affiliates_profile_path, params: {
      affiliate: {
        promotional_methods: "Blog, Social Media, Email Marketing",
        expected_referrals: 100
      }
    }

    assert_redirected_to affiliates_profile_path
    @affiliate.reload
    assert_equal "Blog, Social Media, Email Marketing", @affiliate.promotional_methods
    assert_equal 100, @affiliate.expected_referrals
  end

  test "should not update profile with invalid email" do
    affiliate_login

    patch affiliates_profile_path, params: {
      affiliate: {
        email: "invalid-email"
      }
    }

    assert_response :unprocessable_content
    assert_select "h3", text: /error/
  end

  test "should render edit template on validation failure" do
    affiliate_login

    patch affiliates_profile_path, params: {
      affiliate: {
        email: ""
      }
    }

    assert_response :unprocessable_content
    assert_select "h2", text: /Edit Profile/
  end

  # Update password tests
  test "should update password with correct current password" do
    affiliate_login

    patch update_password_affiliates_profile_path, params: {
      current_password: "password123",
      affiliate: {
        password: "newpassword456",
        password_confirmation: "newpassword456"
      }
    }

    assert_redirected_to affiliates_profile_path
    follow_redirect!
    assert_match "Password updated successfully", response.body

    # Test new password works
    delete logout_affiliates_path
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "newpassword456"
    }
    assert_redirected_to affiliates_dashboard_path
  end

  test "should not update password with incorrect current password" do
    affiliate_login

    patch update_password_affiliates_profile_path, params: {
      current_password: "wrongpassword",
      affiliate: {
        password: "newpassword456",
        password_confirmation: "newpassword456"
      }
    }

    assert_redirected_to edit_affiliates_profile_path
    follow_redirect!
    assert_match "Current password is incorrect", response.body
  end

  test "should not update password when confirmation doesn't match" do
    affiliate_login

    patch update_password_affiliates_profile_path, params: {
      current_password: "password123",
      affiliate: {
        password: "newpassword456",
        password_confirmation: "differentpassword"
      }
    }

    assert_redirected_to edit_affiliates_profile_path
    follow_redirect!
    assert_match "Password update failed", response.body
  end

  test "should not update password when too short" do
    affiliate_login

    patch update_password_affiliates_profile_path, params: {
      current_password: "password123",
      affiliate: {
        password: "short",
        password_confirmation: "short"
      }
    }

    assert_redirected_to edit_affiliates_profile_path
    follow_redirect!
    assert_match "Password update failed", response.body
  end

  # Security tests
  test "should not allow updating other affiliate's profile" do
    affiliate_login
    other_affiliate = affiliates(:pending_affiliate)

    # Try to update with another affiliate's ID (should be ignored)
    patch affiliates_profile_path, params: {
      id: other_affiliate.id,
      affiliate: {
        name: "Hacker"
      }
    }

    @affiliate.reload
    other_affiliate.reload

    # Should update current affiliate, not the other one
    assert_equal "Hacker", @affiliate.name
    assert_not_equal "Hacker", other_affiliate.name
  end

  test "should use current session affiliate only" do
    # Create another active affiliate to test with
    another_active = affiliates(:high_volume)
    affiliate_login(another_active)

    get affiliates_profile_path
    assert_response :success

    # Should show logged-in affiliate's info, not other affiliate's
    assert_select "dd", text: another_active.email
    assert_select "span", text: another_active.code
  end

  # Navigation tests
  test "should have cancel link on edit page" do
    affiliate_login
    get edit_affiliates_profile_path
    assert_response :success
    assert_select "a[href=?]", affiliates_profile_path, text: /Cancel/
  end

  test "should have save changes button on edit page" do
    affiliate_login
    get edit_affiliates_profile_path
    assert_response :success
    assert_select "input[type='submit'][value='Save Changes']"
  end

  test "should have update password button on edit page" do
    affiliate_login
    get edit_affiliates_profile_path
    assert_response :success
    assert_select "input[type='submit'][value='Update Password']"
  end

  # Edge cases
  test "should handle nil values gracefully on show" do
    @affiliate.update_columns(
      name: nil,
      company_name: nil,
      website: nil,
      phone: nil,
      promotional_methods: nil
    )

    affiliate_login
    get affiliates_profile_path
    assert_response :success
    assert_match "Not provided", response.body
  end

  test "should display masked tax ID on show" do
    @affiliate.update(tax_id: "123-45-6789")

    affiliate_login
    get affiliates_profile_path
    assert_response :success

    # Should show only last 4 digits
    assert_match "••••6789", response.body
    assert_no_match "123-45", response.body
  end

  test "should display full address when all parts present" do
    @affiliate.update(
      address: "123 Test St",
      city: "Test City",
      state: "TC",
      postal_code: "12345",
      country: "Test Country"
    )

    affiliate_login
    get affiliates_profile_path
    assert_response :success

    assert_match "123 Test St", response.body
    assert_match "Test City, TC", response.body
    assert_match "12345", response.body
    assert_match "Test Country", response.body
  end

  test "should redirect pending affiliate to login" do
    # Pending affiliates shouldn't be able to access profile
    post login_affiliates_path, params: {
      email: @pending_affiliate.email,
      password: "password123"
    }
    # Session is set but they should be redirected due to status
    get affiliates_profile_path
    assert_redirected_to login_affiliates_path
  end

  test "should preserve form values on validation error" do
    affiliate_login

    patch affiliates_profile_path, params: {
      affiliate: {
        name: "New Name",
        email: "invalid-email",
        company_name: "New Company"
      }
    }

    assert_response :unprocessable_content
    assert_select "input[name='affiliate[name]'][value='New Name']"
    assert_select "input[name='affiliate[company_name]'][value='New Company']"
  end
end
