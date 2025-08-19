require "test_helper"

class AffiliatesIndexRedirectTest < ActionDispatch::IntegrationTest
  def setup
    # Use fixtures instead of creating new records to avoid email duplication
    @affiliate = affiliates(:active_affiliate)
    @suspended_affiliate = affiliates(:suspended_affiliate)
    @pending_affiliate = affiliates(:pending_affiliate)
  end

  def affiliate_login(affiliate = @affiliate)
    post login_affiliates_path, params: {
      email: affiliate.email,
      password: "password123"
    }
    assert_equal affiliate.id, session[:affiliate_id]
  end

  # === Basic Redirect Tests ===

  test "should redirect to login when not authenticated" do
    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  test "should redirect to dashboard when authenticated with active affiliate" do
    affiliate_login
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  test "should redirect to dashboard when authenticated with pending affiliate" do
    affiliate_login(@pending_affiliate)
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  test "should redirect to dashboard when authenticated with suspended affiliate" do
    affiliate_login(@suspended_affiliate)
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  # === Session Management Tests ===

  test "should redirect to login when session is empty" do
    # Ensure no session
    reset!
    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  test "should redirect to login when session has invalid affiliate_id" do
    # Set invalid affiliate ID in session
    get login_affiliates_path # Initialize session
    session[:affiliate_id] = 999999 # Non-existent ID

    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  test "should redirect to login when affiliate in session is deleted" do
    affiliate_login

    # Delete the affiliate
    @affiliate.destroy

    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  test "should handle nil session affiliate_id gracefully" do
    get login_affiliates_path # Initialize session
    session[:affiliate_id] = nil

    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  # === Flow Tests ===

  test "should maintain redirect after login" do
    # Not logged in - redirects to login
    get affiliates_path
    assert_redirected_to login_affiliates_path

    # Login
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_redirected_to affiliates_dashboard_path

    # Now /affiliates redirects to dashboard
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  test "should redirect to login after logout" do
    affiliate_login

    # While logged in, redirects to dashboard
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path

    # Logout
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path

    # After logout, redirects to login
    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  # === Multiple Sessions Tests ===

  test "should handle switching between affiliates" do
    # Login as first affiliate
    affiliate_login(@affiliate)
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path

    # Logout
    delete logout_affiliates_path

    # Login as different affiliate
    affiliate_login(@pending_affiliate)
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  # === Direct Access Tests ===

  test "should be accessible via GET request" do
    affiliate_login

    # GET should work
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  # === URL Helper Tests ===

  test "affiliates_path helper should generate correct URL" do
    assert_equal "/affiliates", affiliates_path
  end

  test "should work with trailing slash" do
    get "/affiliates/"
    assert_redirected_to login_affiliates_path
  end

  # === Integration with Other Pages ===

  test "should provide consistent behavior with manual navigation" do
    # Not logged in
    get affiliates_path
    assert_redirected_to login_affiliates_path
    follow_redirect!
    assert_response :success
    assert_select "h2", "Affiliate Dashboard Login"

    # Login
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_redirected_to affiliates_dashboard_path
    follow_redirect!
    assert_response :success

    # Now /affiliates goes to dashboard
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
    follow_redirect!
    assert_response :success
    assert_select "h2", /Welcome back/
  end

  # === Performance Tests ===

  test "should handle rapid consecutive requests" do
    affiliate_login

    5.times do
      get affiliates_path
      assert_redirected_to affiliates_dashboard_path
    end
  end

  test "should handle rapid login/logout cycles with index redirect" do
    3.times do
      # Not logged in
      get affiliates_path
      assert_redirected_to login_affiliates_path

      # Login
      post login_affiliates_path, params: {
        email: @affiliate.email,
        password: "password123"
      }

      # Logged in
      get affiliates_path
      assert_redirected_to affiliates_dashboard_path

      # Logout
      delete logout_affiliates_path
    end
  end

  # === Edge Cases ===

  test "should handle when affiliate status changes after login" do
    affiliate_login

    # Initially redirects to dashboard
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path

    # Change status to suspended
    @affiliate.update!(status: :suspended)

    # Should still redirect to dashboard (status doesn't affect index redirect)
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  test "should handle database connection issues gracefully" do
    # Set a session that appears valid
    get login_affiliates_path
    session[:affiliate_id] = @affiliate.id

    # Simulate database issue by deleting the affiliate
    @affiliate.destroy

    # Should redirect to login when affiliate doesn't exist
    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  # === Security Tests ===

  test "should not leak information about session state" do
    # Whether logged in or not, the response should be consistent (redirect)
    # Not logged in
    get affiliates_path
    assert_response :redirect

    # Logged in
    affiliate_login
    get affiliates_path
    assert_response :redirect
  end

  test "should not create session on index access" do
    # Access index without session
    get affiliates_path
    assert_redirected_to login_affiliates_path

    # Session should not have affiliate_id
    assert_nil session[:affiliate_id]
  end

  # === Browser Behavior Tests ===

  test "should handle browser back button after login redirect" do
    # Visit /affiliates (redirects to login)
    get affiliates_path
    assert_redirected_to login_affiliates_path

    # Login
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_redirected_to affiliates_dashboard_path

    # Browser back to /affiliates should now redirect to dashboard
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  test "should work as bookmark URL" do
    # User bookmarks /affiliates
    # First visit - not logged in
    get affiliates_path
    assert_redirected_to login_affiliates_path

    # Login and visit bookmark again
    affiliate_login
    get affiliates_path
    assert_redirected_to affiliates_dashboard_path

    # Logout and visit bookmark
    delete logout_affiliates_path
    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  # === RESTful Compliance ===

  test "index action should only redirect not render" do
    # Should never render a view, only redirect
    get affiliates_path
    assert_response :redirect
    assert_nil @response.body.match(/<html/)

    affiliate_login
    get affiliates_path
    assert_response :redirect
    assert_nil @response.body.match(/<html/)
  end

  # === Compatibility Tests ===

  test "should work with various affiliate states" do
    affiliates = [
      @affiliate,
      @pending_affiliate,
      @suspended_affiliate
    ]

    affiliates.each do |affiliate|
      # Reset session
      reset!

      # Test redirect when not logged in
      get affiliates_path
      assert_redirected_to login_affiliates_path

      # Login and test redirect
      affiliate_login(affiliate)
      get affiliates_path
      assert_redirected_to affiliates_dashboard_path
    end
  end
end
