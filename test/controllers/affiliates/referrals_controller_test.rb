require "test_helper"

class Affiliates::ReferralsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Clean up existing data to avoid conflicts
    Admin.destroy_all
    Affiliate.destroy_all
    User.destroy_all
    Plan.destroy_all
    Subscription.destroy_all
    Payment.destroy_all
    Referral.destroy_all
    Commission.destroy_all
    AffiliateClick.destroy_all

    # Create test affiliate
    @affiliate = Affiliate.create!(
      name: "Test Affiliate",
      email: "affiliate@example.com",
      password: "password123",
      password_confirmation: "password123",
      code: "TESTCODE",
      commission_rate: 25.0,
      minimum_payout_amount: 100.00,
      attribution_window_days: 30,
      cookie_duration_days: 30,
      payout_address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
      payout_currency: "btc",
      terms_accepted: true,
      status: :active
    )

    # Create another affiliate for isolation tests
    @other_affiliate = Affiliate.create!(
      name: "Other Affiliate",
      email: "other@example.com",
      password: "password456",
      password_confirmation: "password456",
      code: "OTHERCODE",
      commission_rate: 20.0,
      minimum_payout_amount: 50.00,
      attribution_window_days: 15,
      cookie_duration_days: 30,
      payout_address: "0x742d35Cc6634C0532925a3b844Bc8e1198b5b0e0",
      payout_currency: "eth",
      terms_accepted: true,
      status: :active
    )

    # Create suspended affiliate for testing inactive access
    @suspended_affiliate = Affiliate.create!(
      name: "Suspended Affiliate",
      email: "suspended@example.com",
      password: "password789",
      password_confirmation: "password789",
      code: "SUSPENDED",
      commission_rate: 15.0,
      minimum_payout_amount: 75.00,
      attribution_window_days: 30,
      cookie_duration_days: 30,
      payout_address: "LfmssDyX6iZvKTEKbeUhLcYPvQhYMSebDJ",
      payout_currency: "ltc",
      terms_accepted: true,
      status: :suspended
    )

    # Create test users
    @user1 = User.create!(
      email_address: "user1@example.com",
      status: :active
    )

    @user2 = User.create!(
      email_address: "user2@example.com",
      status: :active
    )

    @user3 = User.create!(
      email_address: "user3@example.com",
      status: :active
    )

    @user4 = User.create!(
      email_address: "user4@example.com",
      status: :active
    )

    # Create test plan
    @plan = Plan.create!(
      name: "Premium Plan",
      price: 19.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 5,
      active: true
    )

    # Create referrals with different statuses
    @pending_referral = Referral.create!(
      affiliate: @affiliate,
      user: @user1,
      status: :pending,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.1"),
      clicked_at: 2.days.ago,
      created_at: 2.days.ago
    )

    @converted_referral = Referral.create!(
      affiliate: @affiliate,
      user: @user2,
      status: :converted,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.2"),
      clicked_at: 10.days.ago,
      converted_at: 8.days.ago,
      created_at: 10.days.ago
    )

    @rejected_referral = Referral.create!(
      affiliate: @affiliate,
      user: @user3,
      status: :rejected,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.3"),
      clicked_at: 15.days.ago,
      created_at: 15.days.ago
    )

    # Create old referral (outside attribution window)
    @old_referral = Referral.create!(
      affiliate: @affiliate,
      user: @user4,
      status: :pending,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.4"),
      clicked_at: 45.days.ago,
      created_at: 45.days.ago
    )

    # Create referral for other affiliate
    @other_referral = Referral.create!(
      affiliate: @other_affiliate,
      user: User.create!(email_address: "other_user@example.com"),
      status: :pending,
      ip_hash: Digest::SHA256.hexdigest("192.168.1.5"),
      clicked_at: 1.day.ago,
      created_at: 1.day.ago
    )

    # Create payment for commission
    @payment = Payment.create!(
      user: @user2,
      plan: @plan,
      amount: 19.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN_TEST_001"
    )

    # Create commission for converted referral
    @commission = Commission.create!(
      affiliate: @affiliate,
      referral: @converted_referral,
      payment: @payment,
      amount: 4.99,
      currency: "USD",
      commission_rate: 25.0,
      status: :approved,
      notes: "Commission for Premium Plan subscription"
    )

    # Create affiliate clicks for tracking
    @click1 = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: @pending_referral.ip_hash,
      user_agent_hash: Digest::SHA256.hexdigest("Mozilla/5.0"),
      referrer: "https://example.com",
      landing_page: "/signup",
      converted: false,
      created_at: @pending_referral.created_at - 10.minutes
    )

    @click2 = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: @converted_referral.ip_hash,
      user_agent_hash: Digest::SHA256.hexdigest("Mozilla/5.0"),
      referrer: "https://blog.example.com",
      landing_page: "/pricing",
      converted: true,
      created_at: @converted_referral.created_at - 30.minutes
    )

    @click3 = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: @converted_referral.ip_hash,
      user_agent_hash: Digest::SHA256.hexdigest("Chrome/98.0"),
      referrer: "https://search.example.com",
      landing_page: "/",
      converted: false,
      created_at: @converted_referral.created_at - 1.hour
    )
  end

  # ========== Authentication Tests ==========

  test "should redirect to login when not authenticated" do
    get affiliates_referrals_url
    assert_redirected_to login_affiliates_url
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should redirect to login when accessing show without authentication" do
    get affiliates_referral_url(@pending_referral)
    assert_redirected_to login_affiliates_url
  end

  test "should allow access when authenticated as affiliate" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success
  end

  test "should redirect suspended affiliate to login" do
    login_as_affiliate(@suspended_affiliate)
    get affiliates_referrals_url
    assert_redirected_to login_affiliates_url
    assert_equal "Please log in to continue", flash[:alert]
  end

  test "should maintain session across requests" do
    login_as_affiliate(@affiliate)

    get affiliates_referrals_url
    assert_response :success

    get affiliates_referral_url(@pending_referral)
    assert_response :success
  end

  # ========== Index Action Tests ==========

  test "should get index" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success
    # Check that the view renders without errors
    assert_select "h1", text: /Referrals/i
  end

  test "should display only current affiliate's referrals" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success

    # Check that current affiliate's referrals are displayed
    assert_match @user1.email_address, response.body
    assert_match @user2.email_address, response.body
    assert_match @user3.email_address, response.body
    assert_match @user4.email_address, response.body
    # Other affiliate's referral should not be displayed
    refute_match "other_user@example.com", response.body
  end

  test "should order referrals by created_at desc" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success

    # Check that referrals appear in the correct order in the HTML
    # The most recent should appear before the older ones
    body_index_user1 = response.body.index(@user1.email_address)
    body_index_user4 = response.body.index(@user4.email_address)
    assert body_index_user1 < body_index_user4, "Recent referral should appear before old referral"
  end

  test "should include user association" do
    login_as_affiliate(@affiliate)

    # Should display user emails without N+1 queries
    get affiliates_referrals_url
    assert_response :success
    # Check that user emails are displayed
    assert_match @user1.email_address, response.body
    assert_match @user2.email_address, response.body
  end

  test "should calculate correct statistics" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success

    # Check that statistics are displayed correctly
    assert_select "dd", text: "4"  # Total
    assert_select "dd", text: "2"  # Pending
    assert_select "dd", text: "1"  # Converted (appears twice)
  end

  test "should paginate referrals" do
    # Create many referrals
    30.times do |i|
      Referral.create!(
        affiliate: @affiliate,
        user: User.create!(email_address: "paginated#{i}@example.com"),
        status: :pending,
        ip_hash: Digest::SHA256.hexdigest("192.168.2.#{i}"),
        clicked_at: i.hours.ago
      )
    end

    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success

    # Should have pagination controls if using Kaminari
    # Not all 34 referrals should be displayed on one page
    assert_select "tbody tr", maximum: 25
  end

  test "should handle page parameter" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url, params: { page: 2 }
    assert_response :success
  end

  test "should handle empty referrals list" do
    # Create affiliate with no referrals
    empty_affiliate = Affiliate.create!(
      name: "Empty Affiliate",
      email: "empty@example.com",
      password: "password123",
      password_confirmation: "password123",
      code: "EMPTY",
      commission_rate: 10.0,
      minimum_payout_amount: 50.00,
      attribution_window_days: 30,
      cookie_duration_days: 30,
      payout_address: "TLZvQ26q6cHFKBzMVyQxzUmPVB8PYpRpNg",
      payout_currency: "usdt",
      terms_accepted: true
    )

    login_as_affiliate(empty_affiliate)
    get affiliates_referrals_url
    assert_response :success

    # Should show "No referrals" message
    assert_match "No referrals", response.body
    assert_select "dd", text: "0"  # Total count should be 0
  end

  # ========== Show Action Tests ==========

  test "should get show for own referral" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@pending_referral)
    assert_response :success
    # Check that referral details are displayed
    assert_match @user1.email_address, response.body
    assert_select "h1", text: /Referral Details/i
  end

  test "should not show other affiliate's referral" do
    login_as_affiliate(@affiliate)

    # Should return 404 for other affiliate's referral
    get affiliates_referral_url(@other_referral)
    assert_response :not_found
  end

  test "should show commission for converted referral" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@converted_referral)
    assert_response :success

    # Check that commission is displayed
    assert_match "Commission", response.body
    assert_match "$4.99", response.body
  end

  test "should not show commission for pending referral" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@pending_referral)
    assert_response :success

    # Commission section should not be displayed
    refute_match "$4.99", response.body
  end

  test "should show related clicks" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@converted_referral)
    assert_response :success

    # Check that click history is displayed
    assert_select "h2", text: /Click History/i
    assert_match "blog.example.com", response.body
    assert_match "search.example.com", response.body
    # The first click with different IP hash shouldn't appear
    # It has referrer "https://example.com" (without subdomain)
    # Check that there are only 2 clicks shown (not 3)
    assert_select "tbody tr", 2
  end

  test "should order clicks by created_at desc" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@converted_referral)
    assert_response :success

    # Check that clicks appear in correct order
    body_index_blog = response.body.index("blog.example.com")
    body_index_search = response.body.index("search.example.com")
    assert body_index_blog < body_index_search, "More recent click should appear first"
  end

  test "should only show clicks before referral creation" do
    # Create a click after the referral
    late_click = AffiliateClick.create!(
      affiliate: @affiliate,
      ip_hash: @converted_referral.ip_hash,
      user_agent_hash: Digest::SHA256.hexdigest("Firefox/95.0"),
      referrer: "https://late.example.com",
      landing_page: "/features",
      converted: false,
      created_at: @converted_referral.created_at + 1.hour
    )

    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@converted_referral)
    assert_response :success

    # Late click should not be displayed
    refute_match "late.example.com", response.body
  end

  test "should handle referral with no clicks" do
    # Create referral without any clicks
    no_click_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "noclick@example.com"),
      status: :pending,
      ip_hash: Digest::SHA256.hexdigest("192.168.99.99"),
      clicked_at: 1.hour.ago
    )

    login_as_affiliate(@affiliate)
    get affiliates_referral_url(no_click_referral)
    assert_response :success

    # Should show "No click history" message
    assert_match "No click history", response.body
  end

  # ========== Security Tests ==========

  test "should not expose other affiliates data through parameter manipulation" do
    login_as_affiliate(@affiliate)

    # Try to access with manipulated affiliate_id parameter
    get affiliates_referral_url(@other_referral), params: { affiliate_id: @other_affiliate.id }
    assert_response :not_found
  end

  test "should handle non-existent referral" do
    login_as_affiliate(@affiliate)

    get affiliates_referral_url(id: 999999)
    assert_response :not_found
  end

  test "should sanitize user input in pagination" do
    login_as_affiliate(@affiliate)

    # Try SQL injection in page parameter
    get affiliates_referrals_url, params: { page: "1; DROP TABLE users;" }
    assert_response :success
  end

  # ========== Performance Tests ==========

  test "should avoid N+1 queries on index" do
    login_as_affiliate(@affiliate)

    # Warm up
    get affiliates_referrals_url

    # Create more referrals
    5.times do |i|
      Referral.create!(
        affiliate: @affiliate,
        user: User.create!(email_address: "n1test#{i}@example.com"),
        status: :pending,
        ip_hash: Digest::SHA256.hexdigest("192.168.10.#{i}"),
        clicked_at: i.minutes.ago
      )
    end

    # Should use includes(:user) to avoid N+1
    assert_queries_count(10) do  # Allow some flexibility
      get affiliates_referrals_url
    end
  end

  test "should handle large datasets efficiently" do
    # Create many referrals
    100.times do |i|
      Referral.create!(
        affiliate: @affiliate,
        user: User.create!(email_address: "perf#{i}@example.com"),
        status: [ :pending, :converted, :rejected ].sample,
        ip_hash: Digest::SHA256.hexdigest("192.168.100.#{i}"),
        clicked_at: i.hours.ago
      )
    end

    login_as_affiliate(@affiliate)

    start_time = Time.current
    get affiliates_referrals_url
    load_time = Time.current - start_time

    assert_response :success
    assert load_time < 2, "Page took too long to load: #{load_time} seconds"
  end

  # ========== Edge Cases ==========

  test "should handle referral with nil converted_at" do
    @converted_referral.update_column(:converted_at, nil)

    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@converted_referral)
    assert_response :success
  end

  test "should handle referral with blank ip_hash" do
    # Skip creating invalid referral since ip_hash is required
    # Instead, update existing referral to have blank ip_hash
    referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "noip@example.com"),
      status: :pending,
      ip_hash: Digest::SHA256.hexdigest("temp"),
      clicked_at: 1.hour.ago
    )
    referral.update_column(:ip_hash, "")

    login_as_affiliate(@affiliate)
    get affiliates_referral_url(referral)
    assert_response :success

    # Should handle empty ip_hash gracefully
    assert_match "No click history", response.body
  end

  test "should handle referral outside attribution window" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@old_referral)
    assert_response :success

    # Should still display old referral
    assert_match @user4.email_address, response.body
    assert_match "No (expired)", response.body  # Outside attribution window
  end

  # ========== View Rendering Tests ==========

  test "should render index view" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success
    assert_select "h1", text: /Referrals/i
  end

  test "should display referral statistics on index" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success

    # Check for stats display
    assert_select "div", text: /Total.*4/
    assert_select "div", text: /Pending.*2/
    assert_select "div", text: /Converted.*1/
  end

  test "should display referral list on index" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url
    assert_response :success

    # Check for referral entries
    assert_select "td", text: @user1.email_address
    assert_select "td", text: @user2.email_address
    assert_select "td", text: /pending/i
    assert_select "td", text: /converted/i
  end

  test "should render show view" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@pending_referral)
    assert_response :success

    assert_select "h1", text: /Referral Details/i
  end

  test "should display user information on show" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@pending_referral)
    assert_response :success

    assert_select "div", text: @user1.email_address
  end

  test "should display commission on show for converted referral" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@converted_referral)
    assert_response :success

    assert_select "div", text: /Commission/
    assert_select "div", text: /\$4\.99/
  end

  test "should display click history on show" do
    login_as_affiliate(@affiliate)
    get affiliates_referral_url(@converted_referral)
    assert_response :success

    assert_select "h2", text: /Click History/i
    assert_select "td", text: /blog\.example\.com/
  end

  # ========== Format Tests ==========

  test "should respond to html format" do
    login_as_affiliate(@affiliate)
    get affiliates_referrals_url, headers: { "Accept" => "text/html" }
    assert_response :success
  end

  test "should not respond to json format" do
    login_as_affiliate(@affiliate)

    # Rails will return 406 Not Acceptable for unsupported formats
    get affiliates_referrals_url, headers: { "Accept" => "application/json" }
    assert_response :not_acceptable
  end

  # ========== Integration Tests ==========

  test "should track referral conversion flow" do
    login_as_affiliate(@affiliate)

    # View pending referral
    get affiliates_referral_url(@pending_referral)
    assert_response :success
    assert_select "span", text: /pending/i

    # Simulate conversion (would normally happen through user action)
    @pending_referral.convert!
    payment = Payment.create!(
      user: @pending_referral.user,
      plan: @plan,
      amount: 19.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN_CONVERT_001"
    )
    Commission.create!(
      affiliate: @affiliate,
      referral: @pending_referral,
      payment: payment,
      amount: 4.99,
      currency: "USD",
      commission_rate: 25.0,
      status: :pending
    )

    # View converted referral
    get affiliates_referral_url(@pending_referral)
    assert_response :success
    assert_select "span", text: /converted/i
    assert_select "div", text: /Commission/
  end

  test "should show correct counts after new referral" do
    login_as_affiliate(@affiliate)

    # Check initial counts
    get affiliates_referrals_url
    assert_response :success
    # Initial: 4 total, 2 pending
    assert_select "dd", text: "4"
    assert_select "dd", text: "2"

    # Create new referral
    new_referral = Referral.create!(
      affiliate: @affiliate,
      user: User.create!(email_address: "newref@example.com"),
      status: :pending,
      ip_hash: Digest::SHA256.hexdigest("192.168.200.1"),
      clicked_at: 1.minute.ago
    )

    # Check updated counts
    get affiliates_referrals_url
    assert_response :success
    # Updated: 5 total, 3 pending
    assert_select "dd", text: "5"
    assert_select "dd", text: "3"
  end

  private

  def login_as_affiliate(affiliate)
    post login_affiliates_url, params: {
      email: affiliate.email,
      password: "password123"
    }
  end

  def assert_queries_count(expected_max)
    queries = []
    counter = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:sql].match?(/SCHEMA|TRANSACTION/)
    end

    yield

    actual_count = queries.size
    assert actual_count <= expected_max,
           "Expected at most #{expected_max} queries but got #{actual_count}:\n#{queries.join("\n")}"
  ensure
    ActiveSupport::Notifications.unsubscribe(counter)
  end
end
