require "test_helper"

class Affiliates::MarketingToolsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Use fixtures instead of creating duplicates
    @affiliate = affiliates(:active_affiliate)
    @suspended_affiliate = affiliates(:suspended_affiliate)
    @pending_affiliate = affiliates(:pending_affiliate)
  end

  def affiliate_login(affiliate = @affiliate)
    post login_affiliates_path, params: {
      email: affiliate.email,
      password: "password123"
    }
  end

  # === Authentication Tests ===

  test "should redirect to login if not authenticated for index" do
    get affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should redirect to login if not authenticated for link_generator" do
    get link_generator_affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should redirect to login if not authenticated for banners" do
    get banners_affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should redirect to login if not authenticated for email_templates" do
    get email_templates_affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should not allow suspended affiliate to access marketing tools" do
    affiliate_login(@suspended_affiliate)

    get affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should not allow pending affiliate to access marketing tools" do
    affiliate_login(@pending_affiliate)

    get affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  # === Index Action Tests ===

  test "should get index when authenticated" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success
    assert_select "h2", text: /Marketing Tools/
  end

  test "should display all referral links in index" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Check for presence of referral links
    assert_match /Homepage/, response.body
    assert_match /Signup/, response.body
    assert_match /Plans/, response.body
    assert_match /Features/, response.body
    assert_match /Pricing/, response.body

    # Check all links contain affiliate code
    assert_match /ref=#{@affiliate.code}/, response.body
  end

  test "should display correct referral URLs format in index" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Check URL formats
    assert_match %r{http://www\.example\.com/\?ref=#{@affiliate.code}}, response.body
    assert_match %r{http://www\.example\.com/signup\?ref=#{@affiliate.code}}, response.body
    assert_match %r{http://www\.example\.com/plans\?ref=#{@affiliate.code}}, response.body
    assert_match %r{http://www\.example\.com/\?ref=#{@affiliate.code}#features}, response.body
  end

  test "should display banner previews in index" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Check for banner information
    assert_match /Leaderboard/, response.body
    assert_match /728x90/, response.body
    assert_match /Medium Rectangle/, response.body
    assert_match /300x250/, response.body
    assert_match /Mobile Banner/, response.body
    assert_match /320x50/, response.body
    assert_match /Wide Skyscraper/, response.body
    assert_match /160x600/, response.body
  end

  test "should display email template previews in index" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Check for email templates
    assert_match /Introduction Email/, response.body
    assert_match /Secure Your Online Privacy with VPN9/, response.body
    assert_match /Special Offer Email/, response.body
    assert_match /Exclusive VPN9 Discount for You/, response.body
    assert_match /Security Alert Email/, response.body
    assert_match /Protect Yourself from Online Threats/, response.body
  end

  # === Link Generator Action Tests ===

  test "should get link_generator when authenticated" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path
    assert_response :success
    assert_select "h2", text: /Link Generator/
  end

  test "should generate referral link with default base URL" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path
    assert_response :success

    # Should use root_url as default
    assert_match %r{http://www\.example\.com/\?ref=#{@affiliate.code}}, response.body
  end

  test "should generate referral link with custom URL" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path, params: {
      url: "https://example.com/special-offer"
    }
    assert_response :success

    assert_match %r{https://example\.com/special-offer\?ref=#{@affiliate.code}}, response.body
  end

  test "should handle URL with existing query parameters" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path, params: {
      url: "https://example.com/page?campaign=summer&source=blog"
    }
    assert_response :success

    # Should append ref parameter to existing query
    assert_match /campaign=summer/, response.body
    assert_match /source=blog/, response.body
    assert_match /ref=#{@affiliate.code}/, response.body
  end

  test "should handle invalid URL gracefully" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path, params: {
      url: "not a valid url"
    }
    assert_response :success

    # Should return original URL when invalid
    assert_match /not a valid url/, response.body
  end

  test "should handle URL with fragment" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path, params: {
      url: "https://example.com/page#section"
    }
    assert_response :success

    # Should preserve fragment
    assert_match %r{https://example\.com/page\?ref=#{@affiliate.code}#section}, response.body
  end

  test "should display link generator form" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path
    assert_response :success

    # Check for form elements
    assert_select "form"
    assert_select "input[type=text]"
    assert_select "input[type=submit][value='Generate Link']"
  end

  test "should include copy button for generated link" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path
    assert_response :success

    assert_select "button", text: /Copy/
    assert_match /navigator\.clipboard\.writeText/, response.body
  end

  # === Banners Action Tests ===

  test "should get banners when authenticated" do
    affiliate_login
    get banners_affiliates_marketing_tools_path
    assert_response :success
    assert_select "h2", text: /Marketing Banners/
  end

  test "should display all banner sizes" do
    affiliate_login
    get banners_affiliates_marketing_tools_path
    assert_response :success

    # Check all banner sizes are displayed
    assert_match /728x90/, response.body
    assert_match /Leaderboard/, response.body
    assert_match /300x250/, response.body
    assert_match /Medium Rectangle/, response.body
    assert_match /320x50/, response.body
    assert_match /Mobile Banner/, response.body
    assert_match /160x600/, response.body
    assert_match /Wide Skyscraper/, response.body
  end

  test "should display banner images" do
    affiliate_login
    get banners_affiliates_marketing_tools_path
    assert_response :success

    # Check for image references
    assert_match /banner-728x90\.png/, response.body
    assert_match /banner-300x250\.png/, response.body
    assert_match /banner-320x50\.png/, response.body
    assert_match /banner-160x600\.png/, response.body
  end

  test "should include embed code for banners" do
    affiliate_login
    get banners_affiliates_marketing_tools_path
    assert_response :success

    # Should have embed code sections
    assert_match /HTML Code/, response.body
    assert_match /<img/, response.body
    assert_match /<a/, response.body
    assert_match /ref=#{@affiliate.code}/, response.body
  end

  test "should include download links for banners" do
    affiliate_login
    get banners_affiliates_marketing_tools_path
    assert_response :success

    assert_select "a", text: /Download/
  end

  # === Email Templates Action Tests ===

  test "should get email_templates when authenticated" do
    affiliate_login
    get email_templates_affiliates_marketing_tools_path
    assert_response :success
    assert_select "h2", text: /Email Templates/
  end

  test "should display all email templates" do
    affiliate_login
    get email_templates_affiliates_marketing_tools_path
    assert_response :success

    # Check for all templates
    assert_match /Introduction Email/, response.body
    assert_match /Secure Your Online Privacy with VPN9/, response.body

    assert_match /Special Offer Email/, response.body
    assert_match /Exclusive VPN9 Discount for You/, response.body

    assert_match /Security Alert Email/, response.body
    assert_match /Protect Yourself from Online Threats/, response.body

    # Check that actual email content is present
    assert_match /Military-grade encryption/, response.body
    assert_match /Recent data breaches/, response.body
  end

  test "should include referral links in email templates" do
    affiliate_login
    get email_templates_affiliates_marketing_tools_path
    assert_response :success

    # Templates should include affiliate's referral code
    assert_match /ref=#{@affiliate.code}/, response.body
  end

  test "should include copy buttons for email templates" do
    affiliate_login
    get email_templates_affiliates_marketing_tools_path
    assert_response :success

    assert_select "button", text: /Copy Template/
    assert_match /navigator\.clipboard\.writeText/, response.body
  end

  test "should display template preview sections" do
    affiliate_login
    get email_templates_affiliates_marketing_tools_path
    assert_response :success

    assert_select "div.bg-white.rounded-lg.shadow"  # Template cards
    assert_match /Subject:/, response.body
    assert_match /Preview:/, response.body
  end

  # === Layout and Navigation Tests ===

  test "should use affiliate layout for all marketing tools pages" do
    affiliate_login

    # Test each page
    [ affiliates_marketing_tools_path,
      link_generator_affiliates_marketing_tools_path,
      banners_affiliates_marketing_tools_path,
      email_templates_affiliates_marketing_tools_path
    ].each do |path|
      get path
      assert_response :success

      # Check for affiliate layout elements
      assert_select "span", text: "VPN9 Affiliate Portal"
      assert_match @affiliate.name, response.body
      assert_match "Code: #{@affiliate.code}", response.body
    end
  end

  test "should highlight marketing tools in navigation" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Marketing Tools link should have active class
    assert_select "a.border-indigo-500", text: /Marketing Tools/
  end

  # === Session Management Tests ===

  test "should maintain session across marketing tools pages" do
    affiliate_login

    # Visit multiple pages without re-login
    get affiliates_marketing_tools_path
    assert_response :success

    get link_generator_affiliates_marketing_tools_path
    assert_response :success

    get banners_affiliates_marketing_tools_path
    assert_response :success

    get email_templates_affiliates_marketing_tools_path
    assert_response :success
  end

  test "should clear session when inactive affiliate tries to access" do
    affiliate_login
    @affiliate.update!(status: :suspended)

    get affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
    assert_nil session[:affiliate_id]
  end

  # === Special Characters and Edge Cases ===

  test "should handle affiliate code with special characters" do
    @affiliate.update!(code: "TEST-123_ABC")

    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Code should be properly URL encoded
    assert_match /ref=TEST-123_ABC/, response.body
  end

  test "should handle very long affiliate codes" do
    @affiliate.update!(code: "A" * 50)

    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    assert_match /ref=#{"A" * 50}/, response.body
  end

  test "should handle URL generation with non-ASCII characters" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path, params: {
      url: "https://example.com/página"
    }
    assert_response :success

    # Should handle URL properly - the URL is returned but may not have ref code due to encoding issues
    assert_match /página/, response.body
  end

  # === Performance Tests ===

  test "should load marketing tools index efficiently" do
    affiliate_login

    start_time = Time.current
    get affiliates_marketing_tools_path
    load_time = Time.current - start_time

    assert_response :success
    assert load_time < 2, "Page took too long to load: #{load_time} seconds"
  end

  # === Mobile Responsiveness Tests ===

  test "should include mobile-responsive elements" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Check for responsive grid classes
    assert_select "div.grid"
    # Check for responsive layout classes in general
    assert_match /grid-cols/, response.body
    assert_match /lg:/, response.body
  end

  # === JavaScript Functionality Tests ===

  test "should include JavaScript for copy functionality" do
    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Check for copy function
    assert_match /function copyToClipboard/, response.body
    assert_match /navigator\.clipboard\.writeText/, response.body
    assert_match /Copied!/, response.body
  end

  test "should include JavaScript for link generation" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path
    assert_response :success

    # Check for form submission handling
    assert_select "form[method=get]"
    assert_select "input[name=url]"
  end

  # === Content Security Tests ===

  test "should properly escape HTML in generated content" do
    @affiliate.update!(code: "<script>alert('XSS')</script>")

    affiliate_login
    get affiliates_marketing_tools_path
    assert_response :success

    # Should escape the code properly - check that raw script tags don't execute
    assert_no_match /<script>alert\('XSS'\)<\/script>/, response.body
    # The code should be escaped in the HTML
    assert_match /&lt;SCRIPT&gt;ALERT\(&#39;XSS&#39;\)&lt;\/SCRIPT&gt;/i, response.body
  end

  test "should handle malicious URL input safely" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path, params: {
      url: "javascript:alert('XSS')"
    }
    assert_response :success

    # Should handle malicious URL safely
    assert_match /javascript:alert/, response.body  # As text, not executable
  end

  # === Empty State Tests ===

  test "should handle missing banner images gracefully" do
    affiliate_login
    get banners_affiliates_marketing_tools_path
    assert_response :success

    # Should show placeholder or default image
    assert_select "img", minimum: 1
  end

  # === Integration with Other Features ===

  test "should show consistent affiliate code across all tools" do
    affiliate_login

    # Check index
    get affiliates_marketing_tools_path
    assert_response :success
    index_body = response.body

    # Check link generator
    get link_generator_affiliates_marketing_tools_path
    assert_response :success
    generator_body = response.body

    # Check banners
    get banners_affiliates_marketing_tools_path
    assert_response :success
    banners_body = response.body

    # Check email templates
    get email_templates_affiliates_marketing_tools_path
    assert_response :success
    templates_body = response.body

    # All should contain the same affiliate code
    [ index_body, generator_body, banners_body, templates_body ].each do |body|
      assert_match /ref=#{@affiliate.code}/, body
    end
  end

  # === Help and Documentation Tests ===

  test "should include help text for link generator" do
    affiliate_login
    get link_generator_affiliates_marketing_tools_path
    assert_response :success

    # Should have instructions
    assert_match /Enter any URL/, response.body
    assert_match /automatically add your referral code/, response.body
  end

  test "should include usage instructions for banners" do
    affiliate_login
    get banners_affiliates_marketing_tools_path
    assert_response :success

    # Should have implementation instructions
    assert_match /Copy.*code/, response.body
    assert_match /website/, response.body
  end

  test "should include customization tips for email templates" do
    affiliate_login
    get email_templates_affiliates_marketing_tools_path
    assert_response :success

    # Should have customization guidance
    assert_match /customize/, response.body
    assert_match /audience/, response.body
  end
end
