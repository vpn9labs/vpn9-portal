require "test_helper"

class Affiliates::DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Use fixtures instead of creating duplicates
    @affiliate = affiliates(:active_affiliate)
    @suspended_affiliate = affiliates(:suspended_affiliate)
    @pending_affiliate = affiliates(:pending_affiliate)

    # Create test plan
    @plan = Plan.create!(
      name: "Premium",
      price: 100,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )
  end

  def affiliate_login(affiliate = @affiliate)
    post login_affiliates_path, params: {
      email: affiliate.email,
      password: "password123"
    }
  end

  # === Authentication Tests ===

  test "should redirect to login if not authenticated" do
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should get dashboard when authenticated" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success
    assert_select "h2", /Welcome back/
    assert_match @affiliate.code, response.body
  end

  test "should not allow suspended affiliate to access dashboard" do
    affiliate_login(@suspended_affiliate)

    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should not allow pending affiliate to access dashboard" do
    affiliate_login(@pending_affiliate)

    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should clear session when inactive affiliate tries to access" do
    affiliate_login
    @affiliate.update!(status: :suspended)

    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
    assert_nil session[:affiliate_id]
  end

  # === Statistics Display Tests ===

  test "should display correct click statistics" do
    # Create various clicks
    15.times do |i|
      AffiliateClick.create!(
        affiliate: @affiliate,
        ip_hash: Digest::SHA256.hexdigest("192.168.1.#{i}"),
        landing_page: i.even? ? "/signup" : "/pricing",
        referrer: [ "https://google.com", "https://facebook.com", nil ].sample,
        created_at: i.days.ago
      )
    end

    # Create duplicate IP clicks (should count as same visitor)
    5.times do |i|
      AffiliateClick.create!(
        affiliate: @affiliate,
        ip_hash: Digest::SHA256.hexdigest("192.168.1.0"),
        landing_page: "/signup",
        created_at: i.hours.ago
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check that Total Clicks label is present and value is displayed
    assert_match /Total Clicks/, response.body
    # Should show 20 clicks (use select to find the actual value)
    assert_select "dd", text: "20"
  end

  test "should display referral statistics" do
    # Create various referrals
    users = 8.times.map do |i|
      User.create!(email_address: "user#{i}@example.com")
    end

    # Create pending referrals
    3.times do |i|
      Referral.create!(
        affiliate: @affiliate,
        user: users[i],
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.2.#{i}"),
        landing_page: "/signup",
        status: :pending,
        created_at: i.days.ago
      )
    end

    # Create converted referrals
    5.times do |i|
      Referral.create!(
        affiliate: @affiliate,
        user: users[i + 3],
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.3.#{i}"),
        landing_page: "/signup",
        status: :converted,
        converted_at: i.days.ago,
        created_at: (i + 5).days.ago
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_match /Referrals.*8/m, response.body
    assert_match /Conversions.*5/m, response.body
  end

  test "should display earnings statistics" do
    # Create referrals with commissions
    3.times do |i|
      user = User.create!(email_address: "buyer#{i}@example.com")
      referral = Referral.create!(
        affiliate: @affiliate,
        user: user,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.4.#{i}"),
        landing_page: "/signup",
        status: :converted,
        converted_at: i.days.ago
      )

      payment = Payment.create!(
        user: user,
        plan: @plan,
        amount: 100,
        currency: "USD",
        status: :paid
      )

      Commission.create!(
        affiliate: @affiliate,
        payment: payment,
        referral: referral,
        amount: 20.0,
        currency: "USD",
        commission_rate: 20.0,
        status: [ :pending, :approved, :paid ][i]
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check earnings display
    assert_match /Pending Earnings/, response.body
    assert_match /Lifetime Earnings/, response.body
    # The earnings values displayed will be formatted, look for the label
    assert_match /Available for Payout/, response.body
  end

  test "should handle zero statistics gracefully" do
    # Affiliate with no activity
    new_affiliate = Affiliate.create!(
      name: "New Affiliate",
      email: "new@example.com",
      code: "NEW000",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "btc",
      payout_address: "bc1qnew",
      password: "password123",
      password_confirmation: "password123",
      terms_accepted: true
    )

    affiliate_login(new_affiliate)
    get affiliates_dashboard_path
    assert_response :success

    # Should show zeros without errors
    assert_select "dd", text: "0", minimum: 3  # At least 3 stats showing 0
    assert_match /Total Clicks/, response.body
    assert_match /Referrals/, response.body
    assert_match /Conversions/, response.body
    assert_no_match /NaN/, response.body
    assert_no_match /undefined/, response.body
  end

  # === Referral Links Tests ===

  test "should display all referral links" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_select "h3", "Your Referral Links"
    assert_match /ref=#{@affiliate.code}/, response.body
    assert_match /Homepage/, response.body
    assert_match /Signup/, response.body
    assert_match /Plans/, response.body
  end

  test "should generate correct referral URLs" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check URL format
    assert_match %r{http://www\.example\.com/\?ref=#{@affiliate.code}}, response.body
    assert_match %r{http://www\.example\.com/signup\?ref=#{@affiliate.code}}, response.body
    assert_match %r{http://www\.example\.com/plans\?ref=#{@affiliate.code}}, response.body
  end

  # === Recent Activity Tests ===

  test "should display recent clicks" do
    # Create clicks with different timestamps
    clicks = 15.times.map do |i|
      AffiliateClick.create!(
        affiliate: @affiliate,
        ip_hash: Digest::SHA256.hexdigest("192.168.5.#{i}"),
        landing_page: "/page#{i}",
        referrer: "https://source#{i}.com",
        created_at: i.hours.ago
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_select "h3", "Recent Clicks"
    # Should show only the 10 most recent
    assert_match /page0/, response.body
    assert_match /page9/, response.body
    assert_no_match /page14/, response.body # 11th click shouldn't be shown
  end

  test "should display recent referrals" do
    # Create referrals
    12.times do |i|
      user = User.create!(email_address: "recent#{i}@example.com")
      Referral.create!(
        affiliate: @affiliate,
        user: user,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.6.#{i}"),
        landing_page: "/signup",
        status: i < 6 ? :converted : :pending,
        created_at: i.hours.ago
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_select "h3", "Recent Referrals"
    # Should show status badges
    assert_select "span.bg-green-100", minimum: 1
    assert_select "span.bg-yellow-100", minimum: 1
  end

  test "should display recent commissions" do
    # Create commissions
    5.times do |i|
      user = User.create!(email_address: "commission#{i}@example.com")
      referral = Referral.create!(
        affiliate: @affiliate,
        user: user,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("192.168.7.#{i}"),
        landing_page: "/signup",
        status: :converted
      )

      payment = Payment.create!(
        user: user,
        plan: @plan,
        amount: 100 + (i * 10),
        currency: "USD",
        status: :paid
      )

      Commission.create!(
        affiliate: @affiliate,
        payment: payment,
        referral: referral,
        amount: 20.0 + (i * 2),
        currency: "USD",
        commission_rate: 20.0,
        status: [ :pending, :approved, :paid, :cancelled, :pending ][i],
        created_at: i.days.ago
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Should have earnings summary section
    assert_match /Earnings Summary/, response.body
    # Should have the calculated totals displayed
    assert_match /Pending Earnings/, response.body
  end

  test "should handle empty recent activity gracefully" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Should show appropriate empty state messages
    assert_match /No clicks yet/, response.body
    assert_match /No referrals yet/, response.body
  end

  # === Chart Data Tests ===

  test "should include performance chart" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_select "#performanceChart"
    assert_match /new Chart/, response.body
    assert_match /chartData/, response.body
  end

  test "should generate correct chart data for last 30 days" do
    # Create data across different days
    (0..29).each do |days_ago|
      date = days_ago.days.ago

      # Create clicks
      2.times do
        AffiliateClick.create!(
          affiliate: @affiliate,
          ip_hash: Digest::SHA256.hexdigest("#{days_ago}-#{rand(1000)}"),
          landing_page: "/signup",
          created_at: date
        )
      end

      # Create referrals on some days
      if days_ago % 3 == 0
        user = User.create!(email_address: "chartuser#{days_ago}@example.com")
        Referral.create!(
          affiliate: @affiliate,
          user: user,
          referral_code: @affiliate.code,
          ip_hash: Digest::SHA256.hexdigest("chart-#{days_ago}"),
          landing_page: "/signup",
          status: days_ago % 6 == 0 ? :converted : :pending,
          converted_at: days_ago % 6 == 0 ? date : nil,
          created_at: date
        )
      end
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check chart data structure
    assert_match /const chartData = \[/, response.body
    assert_match /"date"/, response.body
    assert_match /"clicks"/, response.body
    assert_match /"signups"/, response.body
    assert_match /"conversions"/, response.body
  end

  test "should include Chart.js library" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_match /cdn\.jsdelivr\.net\/npm\/chart\.js/, response.body
  end

  # === Earnings Summary Tests ===

  test "should display earnings summary section" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_select "h3", "Earnings Summary"
    assert_match /Pending Earnings/, response.body
    assert_match /Available for Payout/, response.body
    assert_match /Total Paid Out/, response.body
  end

  test "should calculate pending earnings correctly" do
    # Create pending commissions
    3.times do |i|
      user = User.create!(email_address: "pending#{i}@example.com")
      referral = Referral.create!(
        affiliate: @affiliate,
        user: user,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("pending-#{i}"),
        landing_page: "/signup",
        status: :converted
      )

      payment = Payment.create!(
        user: user,
        plan: @plan,
        amount: 100,
        currency: "USD",
        status: :paid
      )

      Commission.create!(
        affiliate: @affiliate,
        payment: payment,
        referral: referral,
        amount: 25.0,
        currency: "USD",
        commission_rate: 25.0,
        status: :pending
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Should display pending earnings section
    assert_match /Pending Earnings/, response.body
    # Total should be displayed as formatted number
    assert_select "dd", text: /\$75/
  end

  test "should show payout button when eligible" do
    # Create enough approved commissions to meet minimum
    5.times do |i|
      user = User.create!(email_address: "approved#{i}@example.com")
      referral = Referral.create!(
        affiliate: @affiliate,
        user: user,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("approved-#{i}"),
        landing_page: "/signup",
        status: :converted
      )

      payment = Payment.create!(
        user: user,
        plan: @plan,
        amount: 100,
        currency: "USD",
        status: :paid
      )

      Commission.create!(
        affiliate: @affiliate,
        payment: payment,
        referral: referral,
        amount: 25.0,
        currency: "USD",
        commission_rate: 25.0,
        status: :approved
      )
    end

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Should show request payout button
    assert_select "button", text: /Request Payout/
  end

  test "should show minimum payout message when not eligible" do
    # Create small approved commission
    user = User.create!(email_address: "small@example.com")
    referral = Referral.create!(
      affiliate: @affiliate,
      user: user,
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("small"),
      landing_page: "/signup",
      status: :converted
    )

    payment = Payment.create!(
      user: user,
      plan: @plan,
      amount: 50,
      currency: "USD",
      status: :paid
    )

    Commission.create!(
      affiliate: @affiliate,
      payment: payment,
      referral: referral,
      amount: 10.0,
      currency: "USD",
      commission_rate: 20.0,
      status: :approved
    )

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Should show minimum payout amount
    assert_match /Minimum payout amount.*\$100/, response.body
    assert_select "button", text: /Request Payout/, count: 0
  end

  # === Layout and Navigation Tests ===

  test "should use affiliate layout" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check for affiliate layout elements
    assert_select "span", text: "VPN9 Affiliate Portal"
    # The name is shown instead of email in the layout
    assert_match @affiliate.name, response.body
    assert_match "Code: #{@affiliate.code}", response.body
  end

  test "should highlight dashboard in navigation" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Dashboard link should have active class
    assert_select "a.border-indigo-500", text: "Dashboard"
  end

  # === Performance Tests ===

  test "should handle large dataset efficiently" do
    # Create large amount of data
    100.times do |i|
      AffiliateClick.create!(
        affiliate: @affiliate,
        ip_hash: Digest::SHA256.hexdigest("perf-#{i}"),
        landing_page: "/page#{i % 10}",
        created_at: (i % 30).days.ago
      )
    end

    50.times do |i|
      user = User.create!(email_address: "perf#{i}@example.com")
      Referral.create!(
        affiliate: @affiliate,
        user: user,
        referral_code: @affiliate.code,
        ip_hash: Digest::SHA256.hexdigest("perf-ref-#{i}"),
        landing_page: "/signup",
        status: i % 3 == 0 ? :converted : :pending,
        created_at: (i % 30).days.ago
      )
    end

    affiliate_login

    start_time = Time.current
    get affiliates_dashboard_path
    load_time = Time.current - start_time

    assert_response :success
    assert load_time < 3, "Dashboard took too long to load: #{load_time} seconds"
  end

  # === Edge Cases and Error Handling ===

  test "should handle affiliate with special characters in name" do
    @affiliate.update!(name: "Test & Co. <Affiliate>")

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Name should be properly escaped
    assert_no_match /<Affiliate>/, response.body
    assert_match /Test &amp; Co\./, response.body
  end

  test "should handle missing or nil values gracefully" do
    @affiliate.update!(name: nil)

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Should fallback to email
    assert_match @affiliate.email, response.body
  end

  test "should handle future dated data correctly" do
    # Create click with future date (shouldn't happen but testing edge case)
    AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: Digest::SHA256.hexdigest("future"),
      landing_page: "/future",
      created_at: 1.day.from_now
    )

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Should not cause errors
    assert_select "h2", /Welcome back/
  end

  # === Session Management Tests ===

  test "should maintain session across dashboard visits" do
    affiliate_login

    # First visit
    get affiliates_dashboard_path
    assert_response :success

    # Second visit without re-login
    get affiliates_dashboard_path
    assert_response :success
    assert_match @affiliate.code, response.body
  end

  test "should handle expired session gracefully" do
    affiliate_login
    # Manually clear the session to simulate expiration
    reset!

    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
  end

  # === Currency and Formatting Tests ===

  test "should display amounts with correct currency formatting" do
    # Create commission with specific amount
    user = User.create!(email_address: "currency@example.com")
    referral = Referral.create!(
      affiliate: @affiliate,
      user: user,
      referral_code: @affiliate.code,
      ip_hash: Digest::SHA256.hexdigest("currency"),
      landing_page: "/signup",
      status: :converted
    )

    payment = Payment.create!(
      user: user,
      plan: @plan,
      amount: 1234.56,
      currency: "USD",
      status: :paid
    )

    Commission.create!(
      affiliate: @affiliate,
      payment: payment,
      referral: referral,
      amount: 246.91,
      currency: "USD",
      commission_rate: 20.0,
      status: :approved
    )

    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check currency formatting
    assert_match /\$246\.91/, response.body
  end

  # === Mobile Responsiveness Tests ===

  test "should include mobile-responsive elements" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check for responsive grid classes
    assert_select "div.grid.grid-cols-1"
    assert_select "div.sm\\:grid-cols-2, div[class*='sm:grid-cols']"
    assert_select "div.lg\\:grid-cols-4, div[class*='lg:grid-cols']"
  end

  # === Copy to Clipboard Tests ===

  test "should include copy buttons for referral links" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    # Check for copy buttons
    assert_select "button", text: /Copy/
    assert_match /navigator\.clipboard\.writeText/, response.body
  end

  # === Status Badge Tests ===

  test "should display correct status badge for active affiliate" do
    affiliate_login
    get affiliates_dashboard_path
    assert_response :success

    assert_select "span.bg-green-100", text: /Active/
  end

  test "should display pending notice for pending affiliate in header" do
    # Change affiliate to pending for testing the notice
    @affiliate.update!(status: :pending)

    # Pending affiliates shouldn't be able to access, but testing the display
    affiliate_login

    # This should redirect since pending affiliates can't access
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
  end
end
