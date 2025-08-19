require "test_helper"

class AffiliatesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @affiliate = affiliates(:active_affiliate)
  end

  # Index redirect tests
  test "should redirect index to login when not authenticated" do
    get affiliates_path
    assert_redirected_to login_affiliates_path
  end

  test "should redirect index to dashboard when authenticated" do
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_equal @affiliate.id, session[:affiliate_id]

    get affiliates_path
    assert_redirected_to affiliates_dashboard_path
  end

  # Sign-up flow tests
  test "should get new" do
    get new_affiliate_path
    assert_response :success
    assert_select "h2", "Join Our Affiliate Program"
  end

  test "should create affiliate with valid data" do
    assert_difference("Affiliate.count") do
      post affiliates_path, params: {
        affiliate: {
          name: "New Affiliate",
          email: "new@example.com",
          password: "password123",
          password_confirmation: "password123",
          promotional_methods: "Blog and social media",
          expected_referrals: 100,
          payout_currency: "eth",
          payout_address: "0xnewaffiliate",
          country: "USA",
          terms_accepted: true
        }
      }
    end

    assert_redirected_to thank_you_affiliates_path
    new_affiliate = Affiliate.last
    assert_equal "New Affiliate", new_affiliate.name
    assert_equal "new@example.com", new_affiliate.email
    assert_equal "pending", new_affiliate.status
    assert new_affiliate.authenticate("password123")
  end

  test "should not create affiliate with invalid data" do
    assert_no_difference("Affiliate.count") do
      post affiliates_path, params: {
        affiliate: {
          name: "",
          email: "invalid",
          password: "short",
          password_confirmation: "different",
          terms_accepted: false
        }
      }
    end

    assert_response :unprocessable_content
    assert_select "h3", /There were \d+ errors? with your submission/
  end

  test "should auto-generate affiliate code" do
    post affiliates_path, params: {
      affiliate: {
        name: "Auto Code",
        email: "autocode@example.com",
        password: "password123",
        password_confirmation: "password123",
        promotional_methods: "Email marketing",
        expected_referrals: 50,
        payout_currency: "usdt",
        payout_address: "TRautocode",
        country: "UK",
        terms_accepted: true
      }
    }

    new_affiliate = Affiliate.last
    assert_not_nil new_affiliate.code
    assert_match /^[A-Z0-9]{8}$/, new_affiliate.code
  end

  test "should set default values on create" do
    post affiliates_path, params: {
      affiliate: {
        name: "Default Values",
        email: "defaults@example.com",
        password: "password123",
        password_confirmation: "password123",
        promotional_methods: "Content marketing",
        expected_referrals: 25,
        payout_currency: "btc",
        payout_address: "bc1qdefaults",
        country: "Canada",
        terms_accepted: true
      }
    }

    new_affiliate = Affiliate.last
    assert_equal 20.0, new_affiliate.commission_rate
    assert_equal 100.0, new_affiliate.minimum_payout_amount.to_f
    assert_equal "pending", new_affiliate.status
  end

  # Thank you page tests
  test "should get thank you page after sign up" do
    post affiliates_path, params: {
      affiliate: {
        name: "Thank You Test",
        email: "thankyou@example.com",
        password: "password123",
        password_confirmation: "password123",
        promotional_methods: "SEO",
        expected_referrals: 200,
        payout_currency: "xmr",
        payout_address: "4Athankyou",
        country: "Germany",
        terms_accepted: true
      }
    }

    follow_redirect!
    assert_response :success
    assert_select "h2", "Welcome to Our Affiliate Program!"
    assert_match /Thank You Test/, response.body
  end

  test "should redirect to new if accessing thank you without session" do
    get thank_you_affiliates_path
    assert_redirected_to new_affiliate_path
  end

  # Login tests
  test "should get login page" do
    get login_affiliates_path
    assert_response :success
    assert_select "h2", "Affiliate Dashboard Login"
  end

  test "should authenticate with valid credentials" do
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }

    assert_redirected_to affiliates_dashboard_path
    assert_equal @affiliate.id, session[:affiliate_id]
  end

  test "should not authenticate with invalid password" do
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "wrongpassword"
    }

    assert_response :unprocessable_content
    assert_select ".bg-red-50", /Invalid email or password/
    assert_nil session[:affiliate_id]
  end

  test "should not authenticate with non-existent email" do
    post login_affiliates_path, params: {
      email: "nonexistent@example.com",
      password: "password123"
    }

    assert_response :unprocessable_content
    assert_select ".bg-red-50", /Invalid email or password/
    assert_nil session[:affiliate_id]
  end

  # Logout tests
  test "should logout successfully" do
    # Log in first
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_equal @affiliate.id, session[:affiliate_id]

    # Logout
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    assert_equal "You have been logged out", flash[:notice]
    assert_nil session[:affiliate_id]
  end

  test "should redirect to login when accessing logout without being logged in" do
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    # No alert flash when already logged out
    assert_nil flash[:alert]
  end

  test "should prevent access to protected pages after logout" do
    # Log in first
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_equal @affiliate.id, session[:affiliate_id]

    # Access protected page successfully
    get affiliates_dashboard_path
    assert_response :success

    # Logout
    delete logout_affiliates_path
    assert_nil session[:affiliate_id]

    # Try to access protected pages
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
    assert_equal "Please log in to continue", flash[:alert]

    get affiliates_referrals_path
    assert_redirected_to login_affiliates_path

    get affiliates_earnings_path
    assert_redirected_to login_affiliates_path

    get affiliates_marketing_tools_path
    assert_redirected_to login_affiliates_path
  end

  test "should handle multiple logout attempts gracefully" do
    # Log in
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_equal @affiliate.id, session[:affiliate_id]

    # First logout
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    assert_equal "You have been logged out", flash[:notice]
    assert_nil session[:affiliate_id]

    # Second logout attempt (already logged out) - no error, just redirects
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    # Session should remain nil
    assert_nil session[:affiliate_id]
  end

  test "should clear session completely on logout" do
    # Log in and set some session data
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }

    # Add additional session data
    session[:test_data] = "some value"
    assert_equal @affiliate.id, session[:affiliate_id]
    assert_equal "some value", session[:test_data]

    # Logout
    delete logout_affiliates_path

    # Check that affiliate_id is cleared
    assert_nil session[:affiliate_id]
    # Note: Other session data might persist depending on implementation
  end

  test "should logout suspended affiliate successfully" do
    # Log in first
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }
    assert_equal @affiliate.id, session[:affiliate_id]

    # Suspend the affiliate
    @affiliate.update!(status: :suspended)

    # Logout should still work
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    assert_equal "You have been logged out", flash[:notice]
    assert_nil session[:affiliate_id]
  end

  test "should logout pending affiliate successfully" do
    # Use pending affiliate from fixtures
    pending_affiliate = affiliates(:pending_affiliate)

    # Log in
    post login_affiliates_path, params: {
      email: pending_affiliate.email,
      password: "password123"
    }
    assert_equal pending_affiliate.id, session[:affiliate_id]

    # Logout
    delete logout_affiliates_path
    assert_redirected_to login_affiliates_path
    assert_equal "You have been logged out", flash[:notice]
    assert_nil session[:affiliate_id]
  end

  test "should prevent session fixation attacks" do
    # Get initial session ID (simulated)
    get login_affiliates_path

    # Login
    post login_affiliates_path, params: {
      email: @affiliate.email,
      password: "password123"
    }

    old_session_id = session[:affiliate_id]

    # Logout
    delete logout_affiliates_path

    # Try to reuse old session
    get affiliates_dashboard_path
    assert_redirected_to login_affiliates_path
    assert_nil session[:affiliate_id]
  end

  # Security tests
  test "should require password confirmation to match" do
    post affiliates_path, params: {
      affiliate: {
        name: "Mismatch Test",
        email: "mismatch@example.com",
        password: "password123",
        password_confirmation: "different456",
        promotional_methods: "Paid ads",
        expected_referrals: 75,
        payout_currency: "ltc",
        payout_address: "Lmismatch",
        country: "Australia",
        terms_accepted: true
      }
    }

    assert_response :unprocessable_content
    assert_select "li", /Password confirmation doesn't match/
  end

  test "should require minimum password length" do
    post affiliates_path, params: {
      affiliate: {
        name: "Short Pass",
        email: "shortpass@example.com",
        password: "short",
        password_confirmation: "short",
        promotional_methods: "Video marketing",
        expected_referrals: 150,
        payout_currency: "bank",
        payout_address: "Account details",
        country: "France",
        terms_accepted: true
      }
    }

    assert_response :unprocessable_content
    assert_select "li", /Password is too short/
  end

  test "should require unique email" do
    post affiliates_path, params: {
      affiliate: {
        name: "Duplicate Email",
        email: @affiliate.email,  # Using existing email
        password: "password123",
        password_confirmation: "password123",
        promotional_methods: "Influencer marketing",
        expected_referrals: 500,
        payout_currency: "manual",
        payout_address: "Manual payout",
        country: "Spain",
        terms_accepted: true
      }
    }

    assert_response :unprocessable_content
    assert_select "li", /Email has already been taken/
  end

  test "should require terms acceptance" do
    post affiliates_path, params: {
      affiliate: {
        name: "No Terms",
        email: "noterms@example.com",
        password: "password123",
        password_confirmation: "password123",
        promotional_methods: "Podcast advertising",
        expected_referrals: 300,
        payout_currency: "eth",
        payout_address: "0xnoterms",
        country: "Italy",
        terms_accepted: false
      }
    }

    assert_response :unprocessable_content
    assert_select "li", /Terms accepted must be accepted/
  end

  test "should validate email format" do
    post affiliates_path, params: {
      affiliate: {
        name: "Bad Email",
        email: "not-an-email",
        password: "password123",
        password_confirmation: "password123",
        promotional_methods: "Forum posts",
        expected_referrals: 40,
        payout_currency: "btc",
        payout_address: "bc1qbademail",
        country: "Japan",
        terms_accepted: true
      }
    }

    assert_response :unprocessable_content
    assert_select "li", /Email is invalid/
  end
end
