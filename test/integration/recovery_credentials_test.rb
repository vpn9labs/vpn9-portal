require "test_helper"

class RecoveryCredentialsTest < ActionDispatch::IntegrationTest
  test "should display recovery credentials after anonymous signup" do
    # Create anonymous user through signup flow using new account_type parameter
    post signup_url, params: {
      user: {
        account_type: "anonymous"
      }
    }

    assert_response :redirect
    assert_redirected_to root_path

    # Follow the redirect to root which should show recovery credentials
    follow_redirect!

    assert_response :success
    assert_select "h3", text: /Anonymous Account Created Successfully/
    assert_select ".bg-indigo-50", text: /Your Passphrase/
    assert_select ".bg-purple-50", text: /Recovery Code/

    # Should show warning message
    assert_select ".text-red-800", text: /Important: Save These Credentials Now/

    # Should show action buttons
    assert_select "button[onclick*='printCredentials']", text: /Print Credentials/
    assert_select "button[onclick*='copyCredentials']", text: /Copy Passphrase/
    assert_select "a[href*='dismiss=true']", text: /I've Saved Them/
  end

  test "should display recovery credentials after email-only signup" do
    # Create email-only user through signup flow using new account_type parameter
    post signup_url, params: {
      user: {
        account_type: "email",
        email_address: "emailonly@example.com"
      }
    }

    assert_response :redirect
    assert_redirected_to root_path

    # Follow the redirect to root which should show recovery credentials
    follow_redirect!

    assert_response :success
    assert_select "h3", text: /Account Created Successfully/
    assert_select ".bg-indigo-50", text: /Your Passphrase/
    assert_select ".bg-purple-50", text: /Recovery Code/
    # Email accounts don't have passwords in the new flow
    assert_select "p.text-xs.text-indigo-600", text: /This is your complete sign-in credential/
  end

  test "should display recovery credentials after email signup" do
    # In the new flow, email accounts don't use passwords, only passphrases
    post signup_url, params: {
      user: {
        account_type: "email",
        email_address: "full@example.com"
      }
    }

    assert_response :redirect
    assert_redirected_to root_path

    # Follow the redirect to root which should show recovery credentials
    follow_redirect!

    assert_response :success
    assert_select "h3", text: /Account Created Successfully/
    assert_select ".bg-indigo-50", text: /Your Passphrase/
    assert_select ".bg-purple-50", text: /Recovery Code/
    # Email accounts use passphrase-only authentication in the new flow
    assert_select "p.text-xs.text-indigo-600", text: /This is your complete sign-in credential/
  end

  test "should dismiss recovery credentials when requested" do
    # Create anonymous user through signup flow using new account_type parameter
    post signup_url, params: {
      user: {
        account_type: "anonymous"
      }
    }

    assert_response :redirect
    assert_redirected_to root_path

    # Follow the redirect to root which should show recovery credentials
    follow_redirect!

    assert_response :success
    assert_select "h3", text: /Anonymous Account Created Successfully/

    # Dismiss the recovery credentials
    get root_url, params: { dismiss: "true" }

    assert_response :success

    # Subsequent requests should show normal welcome page
    get root_url

    assert_response :success
    assert_select "h1", "Welcome to VPN9"
    refute_select "h3", text: /Account Created Successfully/
  end

  test "should include JavaScript functions for credential management" do
    # Create anonymous user through signup flow using new account_type parameter
    post signup_url, params: {
      user: {
        account_type: "anonymous"
      }
    }

    assert_response :redirect
    assert_redirected_to root_path

    # Follow the redirect to root which should show recovery credentials
    follow_redirect!

    assert_response :success

    # Should include JavaScript functions
    assert_includes response.body, "function copyCredentials()"
    assert_includes response.body, "function printCredentials()"
    assert_includes response.body, "navigator.clipboard.writeText"
    assert_includes response.body, "window.open"
  end

  test "should show actual user credentials in recovery display" do
    # Create anonymous user through signup flow using new account_type parameter
    post signup_url, params: {
      user: {
        account_type: "anonymous"
      }
    }

    assert_response :redirect
    assert_redirected_to root_path

    # Get the created user
    user = User.last

    # Follow the redirect to root which should show recovery credentials
    follow_redirect!

    assert_response :success

    # Should display recovery code
    assert_includes response.body, user.recovery_code

    # Should show passphrase in proper format (7 words separated by hyphens)
    assert_match(/[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+/, response.body)
  end
end
