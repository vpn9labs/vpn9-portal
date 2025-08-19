require "test_helper"

class AccountDeletionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!
    @passphrase = @user.instance_variable_get(:@issued_passphrase)
    sign_in_as(@user)
  end

  test "should get new when authenticated" do
    get new_account_deletion_path
    assert_response :success
    assert_select "h3", "Delete Your Account"
    assert_select "form[action=?]", account_deletion_path
  end

  test "should not get new when not authenticated" do
    sign_out
    get new_account_deletion_path
    assert_redirected_to new_session_path
  end

  test "should delete account with correct passphrase" do
    assert_not @user.deleted?

    assert_difference "Session.count", -1 do
      post account_deletion_path, params: {
        passphrase: @passphrase,
        reason: "Testing account deletion"
      }
    end

    assert_redirected_to root_path
    assert_equal "Your account has been deleted. Your payment history has been preserved for legal requirements.", flash[:notice]

    @user.reload
    assert @user.deleted?
    assert_equal "Testing account deletion", @user.deletion_reason
    assert_nil session[:user_id]
  end

  test "should not delete account with incorrect passphrase" do
    post account_deletion_path, params: {
      passphrase: "wrong-wrong-wrong-wrong-wrong-wrong-wrong",
      reason: "Testing"
    }

    assert_redirected_to new_account_deletion_path
    assert_equal "Invalid passphrase. Please try again.", flash[:alert]

    @user.reload
    assert_not @user.deleted?
  end

  test "should delete account without providing reason" do
    post account_deletion_path, params: {
      passphrase: @passphrase,
      reason: ""
    }

    assert_redirected_to root_path

    @user.reload
    assert @user.deleted?
    assert_nil @user.deletion_reason
  end

  test "should handle account deletion when user has payments" do
    plan = Plan.create!(name: "Test Plan", price: 10, currency: "USD", duration_days: 30)
    payment = @user.payments.create!(
      plan: plan,
      amount: 10,
      currency: "USD",
      status: :paid,
      processor_id: "test-123",
      payment_address: "test-address",
      crypto_currency: "btc",
      crypto_amount: "0.0001"
    )

    post account_deletion_path, params: {
      passphrase: @passphrase
    }

    assert_redirected_to root_path

    payment.reload
    assert_equal @user.id, payment.user_id
    # Payment should be excluded from default scope after user deletion
    assert_not Payment.where(id: payment.id).exists?
    assert Payment.unscoped.exists?(payment.id)
  end

  test "should handle account deletion when user has subscriptions" do
    plan = Plan.create!(name: "Test Plan", price: 10, currency: "USD", duration_days: 30)
    subscription = @user.subscriptions.create!(
      plan: plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    post account_deletion_path, params: {
      passphrase: @passphrase
    }

    assert_redirected_to root_path

    subscription.reload
    assert_equal @user.id, subscription.user_id
    # Subscription should be excluded from default scope after user deletion
    assert_not Subscription.where(id: subscription.id).exists?
    assert Subscription.unscoped.exists?(subscription.id)
  end

  test "should not delete account when not authenticated" do
    sign_out

    post account_deletion_path, params: {
      passphrase: @passphrase
    }

    assert_redirected_to new_session_path

    @user.reload
    assert_not @user.deleted?
  end

  test "should handle passphrase with password" do
    # Create user and capture passphrase before save
    user_with_password = User.new(password: "password123")
    user_with_password.save!
    passphrase_with_password = user_with_password.instance_variable_get(:@issued_passphrase)

    # Verify we have the passphrase
    assert passphrase_with_password.present?, "Passphrase should be available after user creation"

    # Sign in with full identifier (passphrase:password)
    post session_path, params: {
      passphrase: "#{passphrase_with_password}:password123"
    }

    post account_deletion_path, params: {
      passphrase: "#{passphrase_with_password}:password123"
    }

    assert_redirected_to root_path

    user_with_password.reload
    assert user_with_password.deleted?
  end

  test "should handle empty passphrase" do
    post account_deletion_path, params: {
      passphrase: "",
      reason: "Testing"
    }

    assert_redirected_to new_account_deletion_path
    assert_equal "Invalid passphrase. Please try again.", flash[:alert]

    @user.reload
    assert_not @user.deleted?
  end

  test "should handle nil passphrase" do
    post account_deletion_path, params: {
      reason: "Testing"
    }

    assert_redirected_to new_account_deletion_path

    @user.reload
    assert_not @user.deleted?
  end

  test "should handle exception during deletion" do
    User.any_instance.stubs(:soft_delete!).raises(StandardError, "Database error")

    post account_deletion_path, params: {
      passphrase: @passphrase
    }

    assert_redirected_to new_account_deletion_path
    assert_equal "Unable to delete account. Please contact support.", flash[:alert]

    @user.reload
    assert_not @user.deleted?
  end

  test "should not allow deleted user to access deletion page" do
    @user.soft_delete!

    # Try to access with the deleted user's session
    get new_account_deletion_path

    # Should be redirected because deleted users can't authenticate
    assert_redirected_to new_session_path
  end

  test "should show proper warnings on deletion page" do
    get new_account_deletion_path

    assert_select "h3.text-red-800", "Warning: This action cannot be undone"
    assert_select "li", "Your account will be permanently deleted"
    assert_select "li", "You will lose access to all services immediately"
    assert_select "li", "Your email address will be removed from our system"
    assert_select "li", "Payment history will be preserved for legal compliance but anonymized"
  end

  test "should require passphrase field on deletion form" do
    get new_account_deletion_path

    assert_select "input[type=password][name=passphrase][required]"
    assert_select "textarea[name=reason]"
    assert_select "input[type=submit][value=?]", "Delete My Account"
  end

  test "should have cancel link on deletion page" do
    get new_account_deletion_path

    assert_select "a[href=?]", root_path, text: "Cancel"
  end

  test "should handle very long deletion reason" do
    long_reason = "a" * 5000

    post account_deletion_path, params: {
      passphrase: @passphrase,
      reason: long_reason
    }

    assert_redirected_to root_path

    @user.reload
    assert @user.deleted?
    assert_equal long_reason, @user.deletion_reason
  end

  test "should clear session after successful deletion" do
    # Verify user is logged in (has a session)
    get root_path
    assert_response :success

    # Delete account
    post account_deletion_path, params: {
      passphrase: @passphrase
    }

    # Try to access authenticated page - should redirect to login
    get new_account_deletion_path
    assert_redirected_to new_session_path
  end

  private

  def sign_in_as(user)
    post session_path, params: {
      passphrase: user.send(:issued_passphrase)
    }
  end

  def sign_out
    delete session_path
  end
end
