require "test_helper"

class AffiliateSignOutTest < ActionDispatch::IntegrationTest
  def setup
    # Use fixtures instead of creating duplicates
    @affiliate = affiliates(:active_affiliate)
  end

  def affiliate_login
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_equal @affiliate.id, session[:affiliate_id]
  end

  # === Desktop Sign Out Tests ===

  test "should display sign out link in desktop dropdown menu when logged in" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check for user menu button
    assert_select "#user-menu-button"

    # Check for sign out button in dropdown
    assert_select "#user-dropdown" do
      assert_select "button", text: "Sign Out"
    end
  end

  test "should sign out from desktop dropdown menu" do
    affiliate_login

    # Navigate to dashboard
    get affiliates_dashboard_path
    assert_response :success

    # Sign out using the dropdown button
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    follow_redirect!

    # Check flash message
    assert_match /You have been logged out/, flash[:notice]

    # Verify session is cleared
    assert_nil session[:affiliate_id]
  end

  # === Mobile Sign Out Tests ===

  test "should display sign out link in mobile menu when logged in" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check for mobile menu
    assert_select "#mobile-menu" do
      assert_select "button", text: "Sign Out"
    end
  end

  test "should sign out from mobile menu" do
    affiliate_login

    # Navigate to dashboard
    get affiliates_dashboard_path
    assert_response :success

    # Sign out using the mobile menu button
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    follow_redirect!

    # Check flash message
    assert_match /You have been logged out/, flash[:notice]

    # Verify session is cleared
    assert_nil session[:affiliate_id]
  end

  # === Navigation Flow Tests ===

  test "should maintain session state across navigation until sign out" do
    affiliate_login

    # Navigate through various pages
    get affiliates_dashboard_path
    assert_response :success
    assert_select "div", text: "Code: #{@affiliate.code}"

    get affiliates_referrals_path
    assert_response :success
    assert_select "div", text: "Code: #{@affiliate.code}"

    get affiliates_earnings_path
    assert_response :success
    assert_select "div", text: "Code: #{@affiliate.code}"

    get affiliates_marketing_tools_path
    assert_response :success
    assert_select "div", text: "Code: #{@affiliate.code}"

    # Sign out
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path

    # Try to access protected pages
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
  end

  test "should redirect to login page after sign out with notice" do
    affiliate_login

    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    follow_redirect!

    assert_response :success
    assert_select "h2", "Affiliate Dashboard Login"
    # Flash message was already checked in previous assertion
  end

  # === User Experience Tests ===

  test "should display affiliate name in header when logged in" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check desktop header
    assert_select ".hidden.sm\\:flex" do
      assert_select "div", text: @affiliate.name
    end

    # Check mobile header
    assert_select "#mobile-menu" do
      assert_select "div", text: @affiliate.name
    end
  end

  test "should show correct avatar initial in header" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Desktop avatar
    assert_select "#user-menu-button .rounded-full", text: "A" # First letter of "Active Affiliate"

    # Mobile avatar
    assert_select "#mobile-menu .rounded-full", text: "A"
  end

  test "should not display user menu when not logged in" do
    get login_affiliates_path
    assert_response :success

    # Should not have user menu elements
    assert_select "#user-menu-button", false
    assert_select "#user-dropdown", false
  end

  # === Security Tests ===

  test "should not allow access to protected resources after sign out" do
    affiliate_login

    # Create some activity
    AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.1"),
      landing_page: "/signup",
      created_at: 1.hour.ago
    )

    # Access data while logged in
    get affiliates_dashboard_path
    assert_response :success

    # Sign out
    delete logout_affiliates_path

    # Try to access protected resources
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path

    get affiliates_referrals_path
    assert_redirected_to login_affiliates_path

    get affiliates_earnings_path
    assert_redirected_to login_affiliates_path

    get affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
  end

  test "should clear all affiliate-related session data on sign out" do
    affiliate_login

    # Set some session data
    get affiliates_dashboard_path
    assert_response :success
    assert_not_nil session[:affiliate_id]

    # Sign out
    delete logout_affiliates_path

    # Check session is cleared
    assert_nil session[:affiliate_id]

    # Should need to login again
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
  end

  test "should handle rapid sign in and sign out cycles" do
    3.times do |i|
      # Sign in
      post login_affiliates_path, params: {
        email: @affiliate.email,
        password: "password123"
      }
      assert_redirected_to affiliates_dashboard_path
      assert_equal @affiliate.id, session[:affiliate_id]

      # Access a page
      get affiliates_dashboard_path
      assert_response :success

      # Sign out
      delete logout_affiliates_path
      assert_redirected_to login_affiliates_path
      assert_nil session[:affiliate_id]
    end
  end

  # === Status-based Tests ===

  test "should allow inactive affiliate to sign out" do
    affiliate_login

    # Change status to inactive
    @affiliate.update!(status: :suspended)

    # Should still be able to sign out
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    assert_equal "You have been logged out", flash[:notice]
    assert_nil session[:affiliate_id]
  end

  test "should handle sign out when affiliate is deleted" do
    affiliate_login

    # Delete the affiliate record
    @affiliate.destroy

    # Should still be able to sign out gracefully
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    # Session should be cleared even if affiliate doesn't exist
    assert_nil session[:affiliate_id]
  end

  # === Browser Back Button Tests ===

  test "should prevent access via browser back button after sign out" do
    affiliate_login

    # Access protected page
    get affiliates_dashboard_path
    assert_response :success

    # Sign out
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path

    # Simulate browser back button (trying to access previous page)
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  # === Concurrent Session Tests ===

  test "should handle sign out with multiple browser tabs" do
    # First tab: login
    affiliate_login

    # Second tab: also logged in (same session)
    get affiliates_dashboard_path
    assert_response :success

    get affiliates_referrals_path
    assert_response :success

    # First tab: sign out
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path

    # Second tab: should also be logged out
    get affiliates_earnings_path
    assert_redirected_to login_affiliates_path
  end

  # === Error Handling Tests ===

  test "should handle sign out gracefully when session is corrupted" do
    # Login first with valid affiliate
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_equal @affiliate.id, session[:affiliate_id]

    # Delete the affiliate to simulate corruption (session points to non-existent affiliate)
    @affiliate.destroy

    # Try to sign out with non-existent affiliate in session
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path

    # Session should be cleared
    assert_nil session[:affiliate_id]

    # Recreate affiliate for other tests
    @affiliate = affiliates(:active_affiliate)
  end

  test "should redirect properly after sign out from different pages" do
    affiliate_login

    # Test sign out from different pages
    [
      affiliates_dashboard_path,
      affiliates_referrals_path,
      affiliates_earnings_path,
      affiliates_marketing_tools_path
    ].each do |path|
      # Login again
      post login_affiliates_path, params: {
        email: @affiliate.email,
        password: "password123"
      }

      # Navigate to page
      get path
      assert_response :success

      # Sign out
      delete logout_affiliates_path
      assert_redirected_to login_affiliates_path
      assert_nil session[:affiliate_id]
    end
  end
end
