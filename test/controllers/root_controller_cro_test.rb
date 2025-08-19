require "test_helper"

class RootControllerCroTest < ActionDispatch::IntegrationTest
  # === CRO Landing Page Tests ===

  test "should show normal landing page by default" do
    get root_url
    assert_response :success
    assert_select "h1", text: /True Privacy/
    # Should not have CRO elements
    assert_select "#offer-countdown", false
    assert_select "#visitor-counter", false
    assert_select ".trust-badge", false
    assert_no_match "50% OFF", response.body
    assert_no_match "2,847+", response.body
  end

  test "should show CRO landing page with cro=1 parameter" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "h1", text: /True Privacy/
    # Should have CRO elements
    assert_select "#offer-countdown"
    assert_select "#visitor-counter"
    assert_match "2,847+", response.body
    assert_match "50% OFF", response.body
  end

  test "should show CRO landing page with any cro parameter value" do
    get root_url, params: { cro: "true" }
    assert_response :success
    assert_select "#offer-countdown"

    get root_url, params: { cro: "yes" }
    assert_response :success
    assert_select "#offer-countdown"

    get root_url, params: { cro: "anything" }
    assert_response :success
    assert_select "#offer-countdown"
  end

  test "should show normal page when cro parameter is empty" do
    get root_url, params: { cro: "" }
    assert_response :success
    # Empty string is still "present" in Rails params
    assert_select "#offer-countdown", false
  end

  test "CRO page should have testimonials" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_match "Real Users, Real Privacy", response.body
    assert_match "CryptoTrader_89", response.body
    assert_match "PrivacyFirst", response.body
    assert_match "DevSecOps", response.body
  end

  test "CRO page should have urgency elements" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_match "Limited Time Offer", response.body
    assert_match "Special pricing ends soon", response.body
    assert_match "17 spots", response.body
  end

  test "CRO page should have trust badges" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select ".trust-badge", minimum: 3
    assert_match "Open Source", response.body
    assert_match "Audited Code", response.body
    assert_match "No Logs Verified", response.body
  end

  test "CRO page should have enhanced pricing" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select ".line-through", text: "$18"
    assert_match "$9", response.body
    assert_match "50% OFF", response.body
    assert_match "30-Day Money-Back Guarantee", response.body
    assert_match "Get Instant Access", response.body
  end

  test "CRO page should have social proof elements" do
    get root_url, params: { cro: "1" }
    assert_response :success
    # Check for the different variations of the social proof text
    assert_match /2,847\+.*privacy advocates|2,847\+.*users/, response.body
    assert_match "62 people viewing this page", response.body
    assert_select "img.rounded-full", minimum: 4 # Avatar images
  end

  test "normal page should not have CRO JavaScript elements" do
    get root_url
    assert_response :success
    # These elements are only in CRO version
    assert_no_match "showExitIntentOffer", response.body
    assert_no_match "initCountdownTimer", response.body
    assert_no_match "showActivityNotifications", response.body
  end

  test "CRO parameter should work with other URL parameters" do
    get root_url, params: {
      cro: "1",
      utm_source: "google",
      utm_campaign: "test",
      ref: "partner"
    }
    assert_response :success
    assert_select "#offer-countdown"
    assert_match "50% OFF", response.body
  end

  test "both pages should have proper meta tags" do
    # Normal page
    get root_url
    assert_response :success
    assert_select "meta[name='viewport']"
    assert_select "script[type='application/ld+json']"

    # CRO page
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "meta[name='viewport']"
    assert_select "script[type='application/ld+json']"
  end

  test "both pages should have working navigation" do
    # Normal page
    get root_url
    assert_response :success
    assert_select "nav"
    assert_select "a[href='/signup']"
    assert_select "a[href='/session/new']"

    # CRO page
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "nav"
    assert_select "a[href='/signup']"
    assert_select "a[href='/session/new']"
  end

  test "CRO page should have all sections" do
    get root_url, params: { cro: "1" }
    assert_response :success

    # Check all major sections exist
    assert_select "section[aria-label='Hero']"
    assert_select "section[aria-label='Features']"
    assert_select "section[aria-label='How It Works']"
    assert_select "section[aria-label='Testimonials']"
    assert_select "section[aria-label='Pricing']"
    assert_select "section[aria-label='Call to Action']"
  end

  test "authenticated users should see dashboard regardless of CRO parameter" do
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
    assert_select "#offer-countdown", false

    # CRO URL also shows dashboard (not CRO page)
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    assert_select "#offer-countdown", false
  end
end
