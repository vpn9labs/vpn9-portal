require "test_helper"

class RootControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Create a new user each time and store both user and passphrase
    @user = User.new(
      email_address: "test#{SecureRandom.hex(4)}@example.com",
      password: "securepass123",
      password_confirmation: "securepass123"
    )
    @user.save!
    # Capture the passphrase immediately after save - this must be stored
    # as it's only available right after creation
    @user_passphrase = @user.send(:issued_passphrase)
    @user_password = "securepass123"
  end

  # === Unauthenticated Access Tests ===

  test "should show teaser page for unauthenticated users by default" do
    get root_url
    assert_response :success
    # Now shows teaser page by default
    assert_match "True Privacy is", response.body
    assert_match "Coming Soon", response.body
  end

  test "should show full landing page with live parameter" do
    get root_url, params: { live: "1" }
    assert_response :success
    assert_select "h1", text: /True Privacy/
    assert_match "Zero Logs", response.body
  end

  test "should show CRO landing page when cro parameter is present" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "h1", text: /True Privacy/
    # CRO page should have additional elements
    assert_select "#offer-countdown"
    assert_select "#visitor-counter"
    assert_match "2,847+", response.body
    assert_match "50% OFF", response.body
  end

  test "should show normal landing page when cro parameter is empty" do
    get root_url, params: { cro: "" }
    assert_response :success
    assert_select "h1", text: /True Privacy/
    # Should show normal page, not CRO
    assert_select "#offer-countdown", false
    assert_select "#visitor-counter", false
  end

  test "should show CRO landing page when cro parameter is any value" do
    # Controller checks for presence, not specific value
    get root_url, params: { cro: "false" }
    assert_response :success
    assert_select "h1", text: /True Privacy/
    # Will show CRO page since parameter is present
    assert_select "#offer-countdown"
    assert_select "#visitor-counter"
  end

  test "should not store return_to for landing page" do
    get root_url
    assert_nil session[:return_to_after_authenticating]
  end

  test "should not store return_to for CRO landing page" do
    get root_url, params: { cro: "1" }
    assert_nil session[:return_to_after_authenticating]
  end

  # === CRO Landing Page Specific Tests ===

  test "CRO page should have testimonials section" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_match "Real Users, Real Privacy", response.body
    assert_match "CryptoTrader_89", response.body
    assert_match "Finally, a VPN that actually respects privacy", response.body
  end

  test "CRO page should have urgency elements" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_match "Limited Time Offer", response.body
    assert_match "Special pricing ends soon", response.body
    assert_select ".text-yellow-300"
  end

  test "CRO page should have trust badges" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select ".trust-badge"
    assert_match "Open Source", response.body
    assert_match "Audited Code", response.body
    assert_match "No Logs Verified", response.body
  end

  test "CRO page should have enhanced pricing display" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select ".line-through", text: "$18"
    assert_match "50% OFF", response.body
    assert_match "30-Day Money-Back Guarantee", response.body
  end

  test "full landing page should not have CRO elements" do
    get root_url, params: { live: "1" }
    assert_response :success
    # Full page shouldn't have CRO-specific elements
    assert_select "#offer-countdown", false
    assert_select "#visitor-counter", false
    assert_select ".trust-badge", false
    assert_no_match "50% OFF", response.body
    assert_no_match "CryptoTrader_89", response.body
  end

  # === Authenticated Access Tests ===

  test "should get index for authenticated users" do
    sign_in_as(@user)
    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    assert_select "p", text: /You're signed in to your private VPN account/
  end

  test "authenticated users should see dashboard regardless of cro parameter" do
    sign_in_as(@user)
    get root_url, params: { cro: "1" }
    assert_response :success
    # Should still see dashboard, not CRO landing page
    assert_select "h1", "Welcome to VPN9"
    assert_select "p", text: /You're signed in to your private VPN account/
    assert_select "#offer-countdown", false
  end

  test "should show normal welcome page for authenticated users without recovery info" do
    sign_in_as(@user)
    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    assert_select "a.bg-indigo-600", text: "Download VPN Client"
    assert_select "a", text: /Setup Guide/
  end

  test "should handle dismiss parameter when no recovery info exists" do
    sign_in_as(@user)

    get root_url, params: { dismiss: "true" }
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    # Should not cause any errors
  end

  # === Layout and UI Tests ===

  test "should have proper responsive design classes" do
    sign_in_as(@user)
    get root_url
    assert_response :success
    assert_select ".min-h-screen.bg-gray-50"
    assert_select ".max-w-7xl.mx-auto"
    assert_select ".px-4.py-6.sm\\:px-0" # Responsive padding from layout
  end

  test "should include navigation elements" do
    sign_in_as(@user)
    get root_url
    assert_response :success
    assert_select "nav.bg-white"
    assert_select "a", text: "VPN9"
    assert_select "a", text: "Dashboard"
    assert_select "a", text: "Sign out"
  end

  test "should show welcome message and action buttons" do
    sign_in_as(@user)
    get root_url
    assert_response :success
    assert_select "h1", text: "Welcome to VPN9"
    assert_select "p", text: /You're signed in to your private VPN account/
    assert_select "a.bg-indigo-600", text: "Download VPN Client"
    assert_select "a", text: /Setup Guide/
  end

  # === Different User Type Tests ===

  test "should work with email+password users" do
    email_user = User.new(
      email_address: "email@example.com",
      password: "securepass123",
      password_confirmation: "securepass123"
    )
    email_user.save!
    passphrase = email_user.send(:issued_passphrase)

    post session_url, params: {
      passphrase: "#{passphrase}:securepass123",
      email_address: email_user.email_address
    }
    assert_response :redirect
    assert_redirected_to root_path

    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    assert_select "p", text: /You're signed in to your private VPN account/
  end

  test "should work with email-only users" do
    # Create email-only user (no password)
    email_only_user = User.new(email_address: "emailonly@example.com")
    email_only_user.save!
    passphrase = email_only_user.send(:issued_passphrase)

    post session_url, params: {
      passphrase: passphrase,
      email_address: email_only_user.email_address
    }
    assert_response :redirect
    assert_redirected_to root_path

    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
  end

  test "should work with completely anonymous users" do
    # Create completely anonymous user
    anonymous_user = User.create!
    passphrase = anonymous_user.send(:issued_passphrase)

    post session_url, params: {
      passphrase: passphrase
    }
    assert_response :redirect
    assert_redirected_to root_path

    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
  end

  # === Security Tests ===

  test "should not expose recovery info to different authenticated users" do
    # Sign in as first user
    sign_in_as(@user)
    get root_url
    first_response = response.body

    # Sign out and sign in as different user
    delete session_url

    user2 = User.new(
      email_address: "user2@example.com",
      password: "securepass123",
      password_confirmation: "securepass123"
    )
    user2.save!
    passphrase2 = user2.send(:issued_passphrase)

    post session_url, params: {
      passphrase: "#{passphrase2}:securepass123",
      email_address: user2.email_address
    }
    assert_response :redirect
    assert_redirected_to root_path

    get root_url
    assert_response :success
    # Should show normal welcome page for both users
    assert_select "h1", "Welcome to VPN9"
    assert_includes response.body, "Welcome"
  end

  test "should handle concurrent sessions properly" do
    sign_in_as(@user)

    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"

    # Sign out and verify teaser page is shown by default
    delete session_url

    get root_url
    assert_response :success
    # Should show teaser page for unauthenticated users
    assert_match "True Privacy is", response.body
    assert_match "Coming Soon", response.body
  end

  # === Multiple Request Tests ===

  test "should handle multiple requests to root consistently" do
    sign_in_as(@user)

    # First request
    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"

    # Second request should show same content
    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    assert_select "p", text: /You're signed in to your private VPN account/
  end

  test "should handle page refresh after authentication" do
    sign_in_as(@user)

    # Multiple refreshes should work consistently
    3.times do
      get root_url
      assert_response :success
      assert_select "h1", "Welcome to VPN9"
      assert_select "p", text: /You're signed in to your private VPN account/
    end
  end

  # === Error Handling Tests ===

  test "should handle malformed dismiss parameter gracefully" do
    sign_in_as(@user)

    get root_url, params: { dismiss: "invalid_value" }
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
  end

  test "should handle empty dismiss parameter gracefully" do
    sign_in_as(@user)

    get root_url, params: { dismiss: "" }
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
  end

  test "should handle additional parameters gracefully" do
    sign_in_as(@user)

    get root_url, params: { dismiss: "true", extra_param: "should_be_ignored" }
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
  end

  # === CSS and Styling Tests ===

  test "should have proper CSS structure" do
    sign_in_as(@user)
    get root_url
    assert_response :success

    # Check main layout structure
    assert_select ".min-h-full"
    assert_select "nav.bg-white.shadow-sm"
    assert_select "main"
    assert_select ".max-w-7xl"

    # Check welcome page structure
    assert_select ".text-center"
    assert_select ".text-4xl.font-bold"
    assert_select ".mt-6.text-lg"
    assert_select ".mt-10.flex"
  end

  test "should have accessible navigation" do
    sign_in_as(@user)
    get root_url
    assert_response :success

    # Check navigation accessibility
    assert_select "nav" do
      assert_select "a[href='/']", text: "VPN9" # Logo link
      assert_select "a[href='/']", text: "Dashboard" # Dashboard link
      assert_select "a[data-turbo-method='delete']", text: "Sign out" # Sign out link
    end
  end

  test "should have proper button styling" do
    sign_in_as(@user)
    get root_url
    assert_response :success

    # Check action buttons have proper styling
    assert_select "a.bg-indigo-600", text: "Download VPN Client"
    assert_select "a.text-sm.font-semibold", text: /Setup Guide/
  end

  # === CRO Parameter Edge Cases ===

  test "should handle multiple cro parameters gracefully" do
    get root_url, params: { cro: [ "1", "2", "3" ] }
    assert_response :success
    # Should still show CRO page
    assert_select "#offer-countdown"
  end

  test "should handle cro parameter with other params" do
    get root_url, params: { cro: "1", utm_source: "test", utm_campaign: "test" }
    assert_response :success
    assert_select "#offer-countdown"
    assert_match "50% OFF", response.body
  end

  test "should maintain cro parameter in session links" do
    get root_url, params: { cro: "1" }
    assert_response :success
    # Check that signup links maintain context
    assert_select "a[href='/signup']"
  end

  test "CRO page should have proper meta structure" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "script[type='application/ld+json']"
    assert_match "VPN9", response.body
  end

  # === Performance and Structure Tests ===

  test "should load page efficiently" do
    sign_in_as(@user)

    start_time = Time.current
    get root_url
    end_time = Time.current

    assert_response :success
    # Page should load reasonably quickly (within 1 second in tests)
    assert (end_time - start_time) < 1.0, "Page took too long to load"
  end

  test "should have proper HTML structure" do
    sign_in_as(@user)
    get root_url
    assert_response :success

    # Check basic HTML structure
    assert_includes response.body, "<!DOCTYPE html>"
    assert_includes response.body, "<html"
    assert_includes response.body, "<head>"
    assert_includes response.body, "<body"
    assert_includes response.body, "</html>"
  end

  test "should include required meta tags" do
    sign_in_as(@user)
    get root_url
    assert_response :success

    # Check for important meta tags
    assert_select "meta[name='viewport']"
    assert_select "title", "VPN9"
    assert_includes response.body, "apple-mobile-web-app-capable"
  end

  private

  def sign_in_as(user)
    # Get the passphrase - for the main test user, we have it stored
    # For other users, try to get it from the object
    if user == @user && @user_passphrase
      passphrase = @user_passphrase
      password = @user_password
    else
      passphrase = user.send(:issued_passphrase)
      password = nil
    end

    # If passphrase is nil, we can't authenticate
    if passphrase.nil?
      raise "Unable to get passphrase for user authentication in test. " \
            "Make sure to capture issued_passphrase immediately after user creation."
    end

    # Build the authentication parameters
    if user == @user && password
      # Main test user with password
      post session_url, params: {
        passphrase: "#{passphrase}:#{password}",
        email_address: user.email_address
      }
    elsif user.email_address.present?
      # Other users with email but no password
      post session_url, params: {
        passphrase: passphrase,
        email_address: user.email_address
      }
    else
      # Anonymous user
      post session_url, params: {
        passphrase: passphrase
      }
    end

    # Check if authentication was successful and follow redirects if needed
    if response.redirect? && response.location == root_url
      follow_redirect!
    end
  end
end
