require "test_helper"

class RootControllerTeaserTest < ActionDispatch::IntegrationTest
  # === Teaser Landing Page Tests ===

  test "should show teaser page by default" do
    get root_url
    assert_response :success
    # Should have teaser elements by default
    assert_select "section[aria-label='Coming Soon']"
    assert_select "h1", text: /When we launch,.*we won't know.*who you are\./m
    assert_match "Put me on the list", response.body
  end

  test "should show full landing page with live parameter" do
    get root_url, params: { live: "1" }
    assert_response :success
    assert_select "section[aria-label='Hero']"
    assert_select "h1", text: /We don't know.*who you are\..*We can't\./m
    # Should not have teaser elements
    assert_select "section[aria-label='Coming Soon']", false
    assert_no_match "Put me on the list", response.body
  end

  test "should show full landing page with full parameter" do
    get root_url, params: { full: "1" }
    assert_response :success
    assert_select "section[aria-label='Hero']"
    assert_select "h1", text: /We don't know.*who you are\..*We can't\./m
    # Should not have teaser elements
    assert_select "section[aria-label='Coming Soon']", false
    assert_no_match "Put me on the list", response.body
  end

  test "default page should have email signup form" do
    get root_url
    assert_response :success
    assert_select "form#notification-form"
    assert_select "input[type='email'][required]"
    assert_select "button[type='submit']", text: /Notify me at launch/
  end

  test "default page should show launch status" do
    get root_url
    assert_response :success
    assert_match "EARLY ACCESS", response.body
    assert_match "Target", response.body
    assert_match "launch", response.body
  end

  test "default page should have feature preview" do
    get root_url
    assert_response :success
    assert_match "Privacy by", response.body
    assert_match "Anonymous accounts", response.body
    assert_match "Bitcoin payments", response.body
    assert_match "Monero payments", response.body
  end

  test "default page should have social proof counter" do
    get root_url
    assert_response :success
    assert_select "#signup-count"
    assert_match "Currently", response.body
    assert_match "waiting", response.body
  end

  test "full landing page should not have teaser elements" do
    get root_url, params: { live: "1" }
    assert_response :success
    assert_select "form#notification-form", false
    assert_select "section[aria-label='Coming Soon']", false
    assert_select "#signup-count", false
  end

  test "CRO page should not have teaser elements" do
    get root_url, params: { cro: "1" }
    assert_response :success
    assert_select "form#notification-form", false
    assert_select "section[aria-label='Coming Soon']", false
    assert_no_match "Put me on the list", response.body
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
    assert_select "section[aria-label='Coming Soon']"
    assert_select "h1", text: /When we launch,.*we won't know.*who you are\./m
    assert_select "form#notification-form"
  end

  test "default page should have proper meta tags" do
    get root_url
    assert_response :success
    assert_select "script[type='application/ld+json']"
    assert_match "VPN9 is the only VPN whose architecture makes logging impossible", response.body
  end

  test "default page should have footer links" do
    get root_url
    assert_response :success
    assert_select "a[href='https://github.com/vpn9labs']"
    assert_match "GitHub", response.body
  end
end
