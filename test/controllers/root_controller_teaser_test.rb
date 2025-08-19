require "test_helper"

class RootControllerTeaserTest < ActionDispatch::IntegrationTest
  # === Teaser Landing Page Tests ===

  test "should show teaser page by default" do
    get root_url
    assert_response :success
    # Should have teaser elements by default
    assert_match "True Privacy.", response.body
    assert_match "Coming Soon", response.body
    assert_match "Get Early Access", response.body
  end

  test "should show full landing page with live parameter" do
    get root_url, params: { live: "1" }
    assert_response :success
    assert_select "h1", text: /True Privacy/
    # Should not have teaser elements
    assert_no_match "Coming Soon", response.body
    assert_no_match "Get Early Access", response.body
  end

  test "should show full landing page with full parameter" do
    get root_url, params: { full: "1" }
    assert_response :success
    assert_select "h1", text: /True Privacy/
    # Should not have teaser elements
    assert_no_match "Coming Soon", response.body
    assert_no_match "Get Early Access", response.body
  end

  test "default page should have email signup form" do
    get root_url
    assert_response :success
    assert_select "form#notification-form"
    assert_select "input[type='email'][required]"
    assert_select "input[type='submit'][value='Notify Me']"
  end

  test "default page should have countdown element" do
    get root_url
    assert_response :success
    assert_select "#countdown"
    assert_match "Q4 2025", response.body
  end

  test "default page should have feature preview" do
    get root_url
    assert_response :success
    assert_match "Zero Connection Logs", response.body
    assert_match "Anonymous Accounts", response.body
    assert_match "Cryptocurrency Payments", response.body
  end

  test "default page should have social proof counter" do
    get root_url
    assert_response :success
    assert_select "#signup-count"
    assert_match "people waiting", response.body
  end

  test "full landing page should not have teaser elements" do
    get root_url, params: { live: "1" }
    assert_response :success
    assert_select "form#notification-form", false
    assert_select "#countdown", false
    assert_select "#signup-count", false
  end

  test "CRO page should not have teaser elements" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "form#notification-form", false
    assert_no_match "Coming Soon", response.body
    assert_no_match "Get Early Access", response.body
  end

  test "authenticated users should see dashboard regardless of teaser parameter" do
    # Create and sign in user
    user = User.create!
    passphrase = user.send(:issued_passphrase)

    post session_url, params: { passphrase: passphrase }
    assert_redirected_to root_path
    follow_redirect!

    # Normal URL shows dashboard
    get root_url
    assert_response :success
    assert_select "h1", "Welcome to VPN9"

    # Teaser URL also shows dashboard (not teaser page)
    get root_url, params: { teaser: "1" }
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    assert_select "form#notification-form", false
  end

  test "default page should work with other URL parameters" do
    get root_url, params: {
      utm_source: "twitter",
      utm_campaign: "prelaunch",
      ref: "producthunt"
    }
    assert_response :success
    assert_match "True Privacy.", response.body
    assert_select "form#notification-form"
  end

  test "default page should have proper meta tags" do
    get root_url
    assert_response :success
    assert_select "script[type='application/ld+json']"
    assert_match "Revolutionary privacy-focused VPN service launching soon", response.body
  end

  test "default page should have animated background elements" do
    get root_url
    assert_response :success
    # Updated teaser page uses different animations
    assert_select ".animate-pulse"
    assert_select ".blur-3xl"
  end

  test "default page should have footer links" do
    get root_url
    assert_response :success
    assert_select "a[href='https://github.com/vpn9labs']"
    assert_match "View on GitHub", response.body
  end
end
