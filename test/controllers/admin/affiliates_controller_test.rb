require "test_helper"

class Admin::AffiliatesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = Admin.create!(email: "admin@example.com", password: "password123")
    @affiliate = Affiliate.create!(
      name: "Test Affiliate",
      email: "affiliate@example.com",
      code: "TESTCODE",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "btc",
      payout_address: "bc1qtest",
      minimum_payout_amount: 100
    )
  end

  def admin_sign_in
    post admin_session_path, params: { email: @admin.email, password: "password123" }
  end

  test "should redirect to login if not authenticated" do
    get admin_affiliates_path
    assert_redirected_to new_admin_session_path
  end

  test "should get index when authenticated" do
    admin_sign_in
    get admin_affiliates_path
    assert_response :success
    assert_select "h1", "Affiliates"
  end

  test "should show affiliate" do
    admin_sign_in
    get admin_affiliate_path(@affiliate)
    assert_response :success
    assert_match @affiliate.name, response.body
    assert_match @affiliate.code, response.body
  end

  test "should get new affiliate form" do
    admin_sign_in
    get new_admin_affiliate_path
    assert_response :success
    assert_select "h1", "New Affiliate"
  end

  test "should create affiliate" do
    admin_sign_in
    assert_difference("Affiliate.count", 1) do
      post admin_affiliates_path, params: {
        affiliate: {
          name: "New Affiliate",
          email: "new@example.com",
          commission_rate: 15.0,
          status: "active",
          payout_currency: "eth",
          payout_address: "0xtest123"
        }
      }
    end
    assert_redirected_to admin_affiliate_path(Affiliate.order(:created_at).last)
    assert_equal "Affiliate created successfully", flash[:notice]
  end

  test "should auto-generate code if not provided" do
    admin_sign_in
    post admin_affiliates_path, params: {
      affiliate: {
        name: "Auto Code Affiliate",
        email: "auto@example.com",
        commission_rate: 10.0
      }
    }
    affiliate = Affiliate.order(:created_at).last
    assert_not_nil affiliate.code
    assert affiliate.code.length >= 8
  end

  test "should get edit affiliate form" do
    admin_sign_in
    get edit_admin_affiliate_path(@affiliate)
    assert_response :success
    assert_select "h1", "Edit Affiliate"
  end

  test "should update affiliate" do
    admin_sign_in
    patch admin_affiliate_path(@affiliate), params: {
      affiliate: {
        name: "Updated Name",
        commission_rate: 25.0
      }
    }
    assert_redirected_to admin_affiliate_path(@affiliate)
    @affiliate.reload
    assert_equal "Updated Name", @affiliate.name
    assert_equal 25.0, @affiliate.commission_rate
  end

  test "should toggle affiliate status" do
    admin_sign_in
    assert @affiliate.active?

    post toggle_status_admin_affiliate_path(@affiliate)
    assert_redirected_to admin_affiliate_path(@affiliate)

    @affiliate.reload
    assert @affiliate.suspended?
  end

  test "should destroy affiliate" do
    admin_sign_in
    assert_difference("Affiliate.count", -1) do
      delete admin_affiliate_path(@affiliate)
    end
    assert_redirected_to admin_affiliates_path
  end

  test "should detect fraud indicators" do
    admin_sign_in

    # Create suspicious activity
    50.times do
      AffiliateClick.create!(
        affiliate: @affiliate,
        ip_hash: Digest::SHA256.hexdigest("same-ip#{Rails.application.secret_key_base}"),
        landing_page: "/",
        created_at: 1.hour.ago
      )
    end

    get admin_affiliate_path(@affiliate)
    assert_response :success
    assert_match "Fraud Detection Alerts", response.body
  end

  test "should show affiliate metrics" do
    admin_sign_in

    # Create some activity
    5.times do |i|
      ip = "192.168.1.#{i}"
      AffiliateClick.create!(
        affiliate: @affiliate,
        ip_hash: AffiliateClick.hash_ip(ip),
        landing_page: "/"
      )
    end

    user = User.create!(email_address: "referred@example.com")
    referral = Referral.create!(
      affiliate: @affiliate,
      user: user,
      referral_code: @affiliate.code,
      ip_hash: AffiliateClick.hash_ip("192.168.1.100")
    )

    get admin_affiliate_path(@affiliate)
    assert_response :success
    assert_match "Total Clicks", response.body
    assert_match "5", response.body
  end
end
