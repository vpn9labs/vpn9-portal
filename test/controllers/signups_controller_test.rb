require "test_helper"

class SignupsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @valid_email = "test@example.com"
  end

  # === GET /signup ===

  test "should get new signup page" do
    get signup_url
    assert_response :success
    assert_select "h1", "Create Your VPN9 Account"
    assert_select "p", "Choose your preferred account type"
    # Should have two account type options
    assert_select "h2", "Anonymous Account"
    assert_select "h2", "Email Account"
  end

  test "should show privacy-first messaging" do
    get signup_url
    assert_response :success
    # Check for privacy messaging in anonymous account section
    assert_select "span", text: "Maximum Privacy"
    assert_select "span", text: "No personal information required"
  end

  test "should show two distinct signup forms" do
    get signup_url
    assert_response :success
    # Should have two forms - one for anonymous, one for email
    assert_select "form#anonymous-form"
    assert_select "form#email-form"
    # Anonymous form should have hidden account_type field
    assert_select "form#anonymous-form input[type=hidden][name='user[account_type]'][value='anonymous']"
    # Email form should have email input field
    assert_select "form#email-form input[type=email][name='user[email_address]']"
  end

  # === Anonymous User Signup ===

  test "should create anonymous user with account_type anonymous" do
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          account_type: "anonymous"
        }
      }
    end

    user = User.order(:created_at).last
    assert_response :redirect
    assert_redirected_to root_path
    assert_equal "Welcome! Your account has been created. Please save your passphrase - you'll need it to access your account.", flash[:notice]
    assert_nil user.email_address
    assert_not_nil user.passphrase_hash
    assert_not_nil user.recovery_code
  end

  test "should ignore email if provided for anonymous account" do
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          account_type: "anonymous",
          email_address: "should_be_ignored@example.com"
        }
      }
    end

    user = User.order(:created_at).last
    assert_nil user.email_address
  end

  test "should ignore password if provided for anonymous account" do
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          account_type: "anonymous",
          password: "should_be_ignored",
          password_confirmation: "should_be_ignored"
        }
      }
    end

    user = User.order(:created_at).last
    assert_response :redirect
    assert_nil user.email_address
  end

  test "should store credentials in session for anonymous user" do
    post signup_url, params: {
      user: {
        account_type: "anonymous"
      }
    }

    # Follow redirect to see credentials on root page
    follow_redirect!
    assert session[:show_credentials].present?
    assert_equal "anonymous", session[:show_credentials]["account_type"]
    assert session[:show_credentials]["passphrase"].present?
    assert session[:show_credentials]["recovery_code"].present?
  end

  # === Email User Signup (No Password Required) ===

  test "should create user with email only" do
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          account_type: "email",
          email_address: @valid_email
        }
      }
    end

    user = User.order(:created_at).last
    assert_response :redirect
    assert_redirected_to root_path
    # Check flash notice contains success message
    assert flash[:notice].present?
    assert_equal @valid_email, user.email_address
    assert_not_nil user.passphrase_hash
    assert_not_nil user.recovery_code
  end

  test "should require email for email account type" do
    assert_no_difference "User.count" do
      post signup_url, params: {
        user: {
          account_type: "email",
          email_address: ""
        }
      }
    end

    assert_response :unprocessable_content
    # The error message should be shown in the response body
    assert_match "is required for email accounts", response.body
  end

  test "should ignore password fields for email account" do
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          account_type: "email",
          email_address: @valid_email,
          password: "should_be_ignored",
          password_confirmation: "should_be_ignored"
        }
      }
    end

    user = User.order(:created_at).last
    assert_equal @valid_email, user.email_address
    # User should still have passphrase but no custom password
    assert_not_nil user.passphrase_hash
  end

  test "should normalize email address case" do
    post signup_url, params: {
      user: {
        account_type: "email",
        email_address: "TEST@EXAMPLE.COM"
      }
    }

    user = User.order(:created_at).last
    assert_equal "test@example.com", user.email_address
  end

  test "should strip whitespace from email" do
    post signup_url, params: {
      user: {
        account_type: "email",
        email_address: "  test@example.com  "
      }
    }

    user = User.order(:created_at).last
    assert_equal "test@example.com", user.email_address
  end

  test "should store credentials in session for email user" do
    post signup_url, params: {
      user: {
        account_type: "email",
        email_address: @valid_email
      }
    }

    # Follow redirect to see credentials on root page
    follow_redirect!
    assert session[:show_credentials].present?
    assert_equal "email", session[:show_credentials]["account_type"]
    assert session[:show_credentials]["passphrase"].present?
    assert session[:show_credentials]["recovery_code"].present?
  end

  # === Session Creation ===

  test "should create session for new anonymous user" do
    post signup_url, params: {
      user: {
        account_type: "anonymous"
      }
    }

    assert cookies[:session_id].present?
  end

  test "should create session for new email user" do
    post signup_url, params: {
      user: {
        account_type: "email",
        email_address: @valid_email
      }
    }

    assert cookies[:session_id].present?
  end

  # === Email Encryption ===

  test "should encrypt email address in database" do
    post signup_url, params: {
      user: {
        account_type: "email",
        email_address: @valid_email
      }
    }

    user = User.order(:created_at).last
    # Email should be encrypted in database
    quoted_id = ActiveRecord::Base.connection.quote(user.id)
    raw_value = User.connection.execute("SELECT email_address FROM users WHERE id = #{quoted_id}").first["email_address"]
    assert_not_equal @valid_email, raw_value
  end

  # === Validation Tests ===

  test "should reject invalid email format for email account" do
    assert_no_difference "User.count" do
      post signup_url, params: {
        user: {
          account_type: "email",
          email_address: "invalid-email"
        }
      }
    end

    assert_response :unprocessable_content
    # Check that error message is displayed
    assert_match "Email address is invalid", response.body
  end

  test "should handle duplicate email addresses" do
    # Create first user
    User.create!(email_address: @valid_email)

    assert_no_difference "User.count" do
      post signup_url, params: {
        user: {
          account_type: "email",
          email_address: @valid_email
        }
      }
    end

    # Should render the signup page again with error
    assert_response :unprocessable_content
    # Check that error message is displayed
    assert_match "has already been taken", response.body
  end

  # === Rate Limiting ===

  test "should rate limit signup attempts in production" do
    skip "Rate limiting only active in production"

    # Make 5 requests quickly
    5.times do
      post signup_url, params: {
        user: {
          account_type: "anonymous"
        }
      }
    end

    # 6th request should be rate limited
    post signup_url, params: {
      user: {
        account_type: "anonymous"
      }
    }

    assert_redirected_to signup_url
    assert_equal I18n.t("signups.create.try_again_later"), flash[:alert]
  end

  # === Error Handling ===

  test "should handle missing user parameter" do
    post signup_url, params: {}
    assert_response :bad_request
  end

  test "should handle missing account_type" do
    # Without account_type, it should behave like old flow
    # But since password fields are not in the new form,
    # it will create an anonymous-like user
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          email_address: ""
        }
      }
    end

    user = User.order(:created_at).last
    assert_nil user.email_address
  end

  # === Backward Compatibility ===

  test "should handle legacy signup with email only" do
    # Old behavior: email without password creates user
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          email_address: @valid_email
        }
      }
    end

    user = User.order(:created_at).last
    assert_equal @valid_email, user.email_address
    assert_not_nil user.passphrase_hash
  end

  test "should handle legacy signup with no fields" do
    # Old behavior: no fields creates anonymous user
    assert_difference "User.count", 1 do
      post signup_url, params: {
        user: {
          email_address: "",
          password: "",
          password_confirmation: ""
        }
      }
    end

    user = User.order(:created_at).last
    assert_nil user.email_address
    assert_not_nil user.passphrase_hash
  end

  # === Affiliate Tracking ===

  test "should track affiliate referral for anonymous signup" do
    affiliate = Affiliate.create!(
      name: "Test Affiliate",
      code: "TEST123",
      email: "affiliate@example.com",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "btc",
      payout_address: "bc1qtest123"
    )

    # First visit with affiliate code to set the cookie
    get signup_url, params: { ref: affiliate.code }
    assert_response :success

    # Now create the account - should track the referral
    assert_difference "Referral.count", 1 do
      post signup_url, params: {
        user: {
          account_type: "anonymous"
        }
      }
    end

    referral = Referral.order(:created_at).last
    assert_equal affiliate, referral.affiliate
    assert_equal User.order(:created_at).last, referral.user
  end

  test "should track affiliate referral for email signup" do
    affiliate = Affiliate.create!(
      name: "Test Affiliate",
      code: "TEST456",
      email: "affiliate@example.com",
      commission_rate: 20.0,
      status: :active,
      payout_currency: "eth",
      payout_address: "0xtest456"
    )

    # First visit with affiliate code to set the cookie
    get signup_url, params: { ref: affiliate.code }
    assert_response :success

    # Now create the account - should track the referral
    assert_difference "Referral.count", 1 do
      post signup_url, params: {
        user: {
          account_type: "email",
          email_address: @valid_email
        }
      }
    end

    referral = Referral.order(:created_at).last
    assert_equal affiliate, referral.affiliate
    assert_equal User.order(:created_at).last, referral.user
  end

  # === UI Elements ===

  test "should display comparison table" do
    get signup_url
    assert_response :success
    assert_select "h3", "Quick Comparison"
    assert_select "table"
    # Check for key comparison points
    assert_match "Personal information required", response.body
    assert_match "Account recovery", response.body
    assert_match "Privacy level", response.body
  end

  test "should display trade-off warnings" do
    get signup_url
    assert_response :success
    # Anonymous account warning
    assert_select ".bg-amber-50" do
      assert_match "Important Trade-off", response.body
      assert_match "No account recovery if you lose your passphrase", response.body
    end
    # Email account privacy note
    assert_select ".bg-blue-50" do
      assert_match "Privacy Note", response.body
      assert_match "Email required for recovery", response.body
    end
  end

  test "should have proper form structure for email account" do
    get signup_url
    assert_response :success
    assert_select "form#email-form" do
      assert_select "input[type=hidden][name='user[account_type]'][value='email']"
      assert_select "input[type=email][name='user[email_address]']"
      assert_select "input[type=submit][value='Create Email Account']"
      # Should NOT have password fields
      assert_select "input[type=password]", count: 0
    end
  end

  test "should have proper form structure for anonymous account" do
    get signup_url
    assert_response :success
    assert_select "form#anonymous-form" do
      assert_select "input[type=hidden][name='user[account_type]'][value='anonymous']"
      assert_select "input[type=submit][value='Create Anonymous Account']"
      # Should NOT have email or password fields
      assert_select "input[type=email]", count: 0
      assert_select "input[type=password]", count: 0
    end
  end

  test "should link to sign in page" do
    get signup_url
    assert_response :success
    assert_select "a[href='#{new_session_path}']", text: "Sign in"
  end
end
