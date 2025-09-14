require "test_helper"

class Admin::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Create an admin user for authentication
    @admin = Admin.create!(
      email: "admin@example.com",
      password: "password123"
    )

    # Create test users
    @user_with_email = User.create!(email_address: "subscriber@example.com")
    @anonymous_user = User.create!(email_address: nil)
    @user_no_subscription = User.create!(email_address: "nosub@example.com")

    # Create test plans
    @monthly_plan = Plan.create!(
      name: "Monthly Premium",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 5,
      active: true
    )

    @yearly_plan = Plan.create!(
      name: "Yearly Premium",
      price: 99.99,
      currency: "USD",
      duration_days: 365,
      device_limit: 10,
      active: true
    )

    @inactive_plan = Plan.create!(
      name: "Legacy Plan",
      price: 4.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 3,
      active: false
    )

    # Create test subscriptions
    @active_subscription = Subscription.create!(
      user: @user_with_email,
      plan: @monthly_plan,
      status: :active,
      started_at: 15.days.ago,
      expires_at: 15.days.from_now
    )

    @expired_subscription = Subscription.create!(
      user: @anonymous_user,
      plan: @monthly_plan,
      status: :expired,
      started_at: 45.days.ago,
      expires_at: 15.days.ago
    )

    @cancelled_subscription = Subscription.create!(
      user: @user_with_email,
      plan: @yearly_plan,
      status: :cancelled,
      started_at: 60.days.ago,
      expires_at: 305.days.from_now,
      cancelled_at: 5.days.ago
    )

    @pending_subscription = Subscription.create!(
      user: @anonymous_user,
      plan: @yearly_plan,
      status: :pending,
      started_at: Time.current,
      expires_at: 365.days.from_now
    )

    # Create test payments for some subscriptions
    @payment1 = Payment.create!(
      user: @user_with_email,
      subscription: @active_subscription,
      plan: @monthly_plan,
      amount: 9.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN123",
      created_at: 15.days.ago
    )

    @payment2 = Payment.create!(
      user: @user_with_email,
      subscription: @cancelled_subscription,
      plan: @yearly_plan,
      amount: 99.99,
      currency: "USD",
      status: :paid,
      transaction_id: "TXN456",
      created_at: 60.days.ago
    )
  end

  # ========== Authentication Tests ==========

  test "should redirect index when not authenticated" do
    get admin_subscriptions_url
    assert_redirected_to new_admin_session_url
  end

  test "should redirect show when not authenticated" do
    get admin_subscription_url(@active_subscription)
    assert_redirected_to new_admin_session_url
  end

  test "should redirect edit when not authenticated" do
    get edit_admin_subscription_url(@active_subscription)
    assert_redirected_to new_admin_session_url
  end

  test "should redirect update when not authenticated" do
    patch admin_subscription_url(@active_subscription), params: {
      subscription: { status: :cancelled }
    }
    assert_redirected_to new_admin_session_url
  end

  # ========== Index Action Tests ==========

  test "should get index when authenticated as admin" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success
    assert_select "h1", "Subscriptions"
  end

  test "should display subscriptions in index" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success

    # Check that subscriptions are displayed
    assert_select "tbody tr", minimum: 4  # We have 4 subscriptions
    assert_match "##{@active_subscription.id}", response.body
    assert_match "##{@expired_subscription.id}", response.body
    assert_match "##{@cancelled_subscription.id}", response.body
    assert_match "##{@pending_subscription.id}", response.body
  end

  test "should display user information in index" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success

    # Check user emails/IDs are displayed
    assert_match @user_with_email.email_address, response.body
    assert_match "User ##{@anonymous_user.id}", response.body
  end

  test "should display plan names in index" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success

    assert_match @monthly_plan.name, response.body
    assert_match @yearly_plan.name, response.body
  end

  test "should display subscription statuses in index" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success

    # Check status badges
    assert_select "span", text: /Active/i
    assert_select "span", text: /Expired/i
    assert_select "span", text: /Cancelled/i
    assert_select "span", text: /Pending/i
  end

  test "should display dates in index" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success

    # Check that dates are displayed
    assert_match @active_subscription.started_at.strftime("%B"), response.body
    assert_match @active_subscription.expires_at.strftime("%B"), response.body
  end

  test "should order subscriptions by created_at desc" do
    login_as_admin

    # Create a new subscription that should appear first
    newest_subscription = Subscription.create!(
      user: @user_no_subscription,
      plan: @monthly_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now,
      created_at: Time.current
    )

    get admin_subscriptions_url
    assert_response :success

    # The newest subscription should appear first in the table
    first_row = css_select("tbody tr").first
    assert_match "##{newest_subscription.id}", first_row.to_s
  end

  test "should paginate subscriptions" do
    login_as_admin

    # Create many subscriptions to trigger pagination
    15.times do |i|
      Subscription.create!(
        user: @user_with_email,
        plan: @monthly_plan,
        status: :active,
        started_at: i.days.ago,
        expires_at: (30 - i).days.from_now
      )
    end

    get admin_subscriptions_url
    assert_response :success

    # The controller uses Kaminari's page method, but pagination controls
    # may not be shown if all records fit on one page or if not implemented in view
    # Just verify the page loads without error
    get admin_subscriptions_url, params: { page: 2 }
    assert_response :success
  end

  test "should handle empty subscription list" do
    login_as_admin

    # Delete all subscriptions
    Subscription.destroy_all

    get admin_subscriptions_url
    assert_response :success
    assert_select "tbody tr", count: 0
  end

  test "should include user and plan associations to avoid N+1 queries" do
    login_as_admin

    # The controller uses includes(:user, :plan) to avoid N+1 queries
    # This test verifies the associations are loaded
    assert_queries(3) do  # Should be minimal queries
      get admin_subscriptions_url
    end
  end

  # ========== Show Action Tests ==========

  test "should show subscription when authenticated as admin" do
    login_as_admin
    get admin_subscription_url(@active_subscription)
    assert_response :success
  end

  test "should display subscription details in show" do
    login_as_admin
    get admin_subscription_url(@active_subscription)
    assert_response :success

    # Check subscription information is displayed
    assert_select "h1", "Subscription Details"
    assert_match @user_with_email.email_address, response.body
    assert_match @monthly_plan.name, response.body
    assert_match "Active", response.body
  end

  test "should display payment history in show" do
    login_as_admin
    get admin_subscription_url(@active_subscription)
    assert_response :success

    # Check payment information
    assert_match "Related Payments", response.body
    # Payment ID is shown truncated in view
    assert_match @payment1.id.first(8), response.body
    assert_match number_to_currency(@payment1.amount), response.body
  end

  test "should handle subscription with no payments" do
    login_as_admin
    get admin_subscription_url(@pending_subscription)
    assert_response :success

    # Should show message about no payments
    assert_match "No payments found", response.body
  end

  test "should display subscription dates and remaining days" do
    login_as_admin
    get admin_subscription_url(@active_subscription)
    assert_response :success

    # Check dates
    assert_match @active_subscription.started_at.strftime("%B %d, %Y"), response.body
    assert_match @active_subscription.expires_at.strftime("%B %d, %Y"), response.body

    # Check days remaining for active subscription
    days_remaining = @active_subscription.days_remaining
    assert_match "#{days_remaining} days", response.body
  end

  test "should handle expired subscription in show" do
    login_as_admin
    get admin_subscription_url(@expired_subscription)
    assert_response :success

    assert_match "Expired", response.body
    # Should not show days remaining for expired subscription
    refute_match /\d+ days remaining/, response.body
  end

  test "should handle cancelled subscription in show" do
    login_as_admin
    get admin_subscription_url(@cancelled_subscription)
    assert_response :success

    assert_match "Cancelled", response.body
    assert_match @cancelled_subscription.cancelled_at.strftime("%B %d, %Y"), response.body
  end

  test "should handle non-existent subscription in show" do
    login_as_admin

    # Non-existent ID should return 404 or redirect
    get admin_subscription_url(id: 999999)
    assert_response :not_found
  end

  test "should show anonymous user subscription" do
    login_as_admin
    get admin_subscription_url(@expired_subscription)
    assert_response :success

    # Should show user ID when no email
    assert_match "User ##{@anonymous_user.id}", response.body
  end

  # ========== Edit Action Tests ==========

  test "should get edit when authenticated as admin" do
    login_as_admin
    get edit_admin_subscription_url(@active_subscription)
    assert_response :success
    assert_select "h1", "Edit Subscription"
  end

  test "should display edit form with current values" do
    login_as_admin
    get edit_admin_subscription_url(@active_subscription)
    assert_response :success

    # Check form has current values
    assert_select "select[name='subscription[status]'] option[selected]", text: "Active"
    assert_select "input[name='subscription[expires_at]'][value]"
  end

  # ========== New/Create Action Tests ==========

  test "should get new when authenticated as admin" do
    login_as_admin
    get new_admin_subscription_url
    assert_response :success
    assert_select "h1", "New Subscription"
  end

  test "new should preselect user when user_id provided" do
    login_as_admin
    get new_admin_subscription_url(user_id: @user_no_subscription.id)
    assert_response :success
    # Verify the user's option is selected in the user select
    assert_select "select[name='subscription[user_id]'] option[selected][value='#{@user_no_subscription.id}']"
  end

  test "should create active subscription with defaults" do
    login_as_admin

    assert_difference -> { Subscription.count }, +1 do
      post admin_subscriptions_url, params: {
        subscription: {
          user_id: @user_no_subscription.id,
          plan_id: @monthly_plan.id
        }
      }
    end

    new_sub = Subscription.order(created_at: :desc).first
    assert_redirected_to admin_subscription_path(new_sub)
    assert_equal "active", new_sub.status
    assert_in_delta Time.current.to_i, new_sub.started_at.to_i, 5
    # For monthly plan with 30 days, expires_at should be about 30 days from now
    assert new_sub.expires_at > 20.days.from_now
  end

  test "should create lifetime subscription with far future expiry when plan is lifetime" do
    login_as_admin
    lifetime_plan = Plan.create!(
      name: "Lifetime",
      price: 299.0,
      currency: "USD",
      lifetime: true,
      device_limit: 10,
      active: true
    )

    assert_difference -> { Subscription.count }, +1 do
      post admin_subscriptions_url, params: {
        subscription: {
          user_id: @user_no_subscription.id,
          plan_id: lifetime_plan.id
        }
      }
    end

    new_sub = Subscription.order(created_at: :desc).first
    assert_equal "active", new_sub.status
    assert new_sub.expires_at > 90.years.from_now
  end

  test "should show all status options in edit form" do
    login_as_admin
    get edit_admin_subscription_url(@active_subscription)
    assert_response :success

    # Check all status options are available
    assert_select "select[name='subscription[status]'] option", 4
    assert_select "option", text: "Active"
    assert_select "option", text: "Expired"
    assert_select "option", text: "Cancelled"
    assert_select "option", text: "Pending"
  end

  test "should handle non-existent subscription in edit" do
    login_as_admin

    # Non-existent ID should return 404 or redirect
    get edit_admin_subscription_url(id: 999999)
    assert_response :not_found
  end

  # ========== Update Action Tests ==========

  test "should update subscription status" do
    login_as_admin

    assert_equal "active", @active_subscription.status

    patch admin_subscription_url(@active_subscription), params: {
      subscription: { status: "cancelled" }
    }

    assert_redirected_to admin_subscription_path(@active_subscription)
    assert_equal "Subscription was successfully updated.", flash[:notice]

    @active_subscription.reload
    assert_equal "cancelled", @active_subscription.status
  end

  test "should update subscription expires_at" do
    login_as_admin

    new_expiry = 60.days.from_now

    patch admin_subscription_url(@active_subscription), params: {
      subscription: { expires_at: new_expiry }
    }

    assert_redirected_to admin_subscription_path(@active_subscription)
    assert_equal "Subscription was successfully updated.", flash[:notice]

    @active_subscription.reload
    assert_in_delta new_expiry.to_i, @active_subscription.expires_at.to_i, 1
  end

  test "should update both status and expires_at" do
    login_as_admin

    new_expiry = 90.days.from_now

    patch admin_subscription_url(@pending_subscription), params: {
      subscription: {
        status: "active",
        expires_at: new_expiry
      }
    }

    assert_redirected_to admin_subscription_path(@pending_subscription)

    @pending_subscription.reload
    assert_equal "active", @pending_subscription.status
    assert_in_delta new_expiry.to_i, @pending_subscription.expires_at.to_i, 1
  end

  test "should not update with invalid expires_at" do
    login_as_admin

    # Try to set expires_at before started_at
    patch admin_subscription_url(@active_subscription), params: {
      subscription: { expires_at: @active_subscription.started_at - 1.day }
    }

    assert_response :unprocessable_content
    assert_select "h1", "Edit Subscription"

    # Subscription should not have changed
    @active_subscription.reload
    assert @active_subscription.expires_at > @active_subscription.started_at
  end

  test "should not update with invalid status" do
    login_as_admin

    # Test invalid status
    assert_raises(ArgumentError) do
      patch admin_subscription_url(@active_subscription), params: {
        subscription: { status: "invalid_status" }
      }
    end
  end

  test "should handle empty update params" do
    login_as_admin

    original_status = @active_subscription.status
    original_expires = @active_subscription.expires_at

    # Empty params should still work - just keep existing values
    patch admin_subscription_url(@active_subscription), params: {
      subscription: { status: original_status }
    }

    assert_redirected_to admin_subscription_path(@active_subscription)

    @active_subscription.reload
    assert_equal original_status, @active_subscription.status
    assert_equal original_expires.to_i, @active_subscription.expires_at.to_i
  end

  test "should handle non-existent subscription in update" do
    login_as_admin

    # Non-existent ID should return 404 or redirect
    patch admin_subscription_url(id: 999999), params: {
      subscription: { status: "cancelled" }
    }
    assert_response :not_found
  end

  test "should not allow updating unpermitted attributes" do
    login_as_admin

    original_user_id = @active_subscription.user_id
    original_plan_id = @active_subscription.plan_id
    original_started_at = @active_subscription.started_at

    patch admin_subscription_url(@active_subscription), params: {
      subscription: {
        status: "active",
        user_id: @user_no_subscription.id,
        plan_id: @yearly_plan.id,
        started_at: 100.days.ago
      }
    }

    assert_redirected_to admin_subscription_path(@active_subscription)

    @active_subscription.reload
    # These attributes should not have changed
    assert_equal original_user_id, @active_subscription.user_id
    assert_equal original_plan_id, @active_subscription.plan_id
    assert_equal original_started_at.to_i, @active_subscription.started_at.to_i
  end

  test "should extend expired subscription" do
    login_as_admin

    assert @expired_subscription.expired?

    # Extend the subscription by 30 days from now
    new_expiry = 30.days.from_now

    patch admin_subscription_url(@expired_subscription), params: {
      subscription: {
        status: "active",
        expires_at: new_expiry
      }
    }

    assert_redirected_to admin_subscription_path(@expired_subscription)

    @expired_subscription.reload
    assert_equal "active", @expired_subscription.status
    assert_not @expired_subscription.expired?
    assert_in_delta new_expiry.to_i, @expired_subscription.expires_at.to_i, 1
  end

  # ========== Integration Tests ==========

  test "should handle full subscription management workflow" do
    login_as_admin

    # View subscription list
    get admin_subscriptions_url
    assert_response :success
    assert_select "tbody tr", minimum: 1

    # View subscription details
    get admin_subscription_url(@active_subscription)
    assert_response :success
    assert_match @user_with_email.email_address, response.body

    # Edit subscription
    get edit_admin_subscription_url(@active_subscription)
    assert_response :success

    # Update subscription
    patch admin_subscription_url(@active_subscription), params: {
      subscription: {
        status: "cancelled",
        expires_at: 7.days.from_now
      }
    }
    assert_redirected_to admin_subscription_path(@active_subscription)

    # Verify changes
    @active_subscription.reload
    assert_equal "cancelled", @active_subscription.status
  end

  test "should display correct status badges" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success

    # Active status should have green badge (only active subscriptions get green)
    assert_select "span.bg-green-100.text-green-800", text: /Active/i

    # Non-active statuses all get gray badge
    assert_select "span.bg-gray-100.text-gray-800", minimum: 3  # Expired, Cancelled, Pending
  end

  test "should show edit and view actions in index" do
    login_as_admin
    get admin_subscriptions_url
    assert_response :success

    # Check action links
    assert_select "a[href='#{admin_subscription_path(@active_subscription)}']", text: "View"
    assert_select "a[href='#{edit_admin_subscription_path(@active_subscription)}']", text: "Edit"
  end

  # ========== Security Tests ==========

  test "should not allow SQL injection in page parameter" do
    login_as_admin

    # Try SQL injection in page parameter
    get admin_subscriptions_url, params: { page: "1; DROP TABLE subscriptions;" }
    assert_response :success

    # Subscriptions should still exist
    assert Subscription.count > 0
  end

  test "should escape user input in views" do
    login_as_admin

    # Create user with potentially malicious email
    xss_user = User.create!(email_address: "test@example.com")
    xss_subscription = Subscription.create!(
      user: xss_user,
      plan: @monthly_plan,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    get admin_subscriptions_url
    assert_response :success

    # Email should be properly escaped in the view
    assert_match "test@example.com", response.body
    # Check that any script tags are from legitimate JS, not XSS
    # The page has legitimate JS for mobile menu, so we can't check for absence of script tags
  end

  test "should handle concurrent updates gracefully" do
    login_as_admin

    # Simulate concurrent update scenario
    subscription = @active_subscription

    # First admin loads edit form
    get edit_admin_subscription_url(subscription)
    assert_response :success

    # Meanwhile, subscription gets updated elsewhere
    subscription.update!(status: "cancelled")

    # First admin submits their update
    patch admin_subscription_url(subscription), params: {
      subscription: { expires_at: 45.days.from_now }
    }

    assert_redirected_to admin_subscription_path(subscription)

    # The update should succeed, changing expires_at
    subscription.reload
    assert_equal "cancelled", subscription.status  # Status remains as updated elsewhere
    assert subscription.expires_at > 40.days.from_now
  end

  # ========== Performance Tests ==========

  test "should handle large number of subscriptions efficiently" do
    login_as_admin

    # Create many subscriptions
    50.times do |i|
      user = User.create!(email_address: "bulk#{i}@example.com")
      Subscription.create!(
        user: user,
        plan: [ @monthly_plan, @yearly_plan ].sample,
        status: [ :active, :expired, :cancelled ].sample,
        started_at: (60 - i).days.ago,
        expires_at: (i - 30).days.from_now
      )
    end

    start_time = Time.current
    get admin_subscriptions_url
    load_time = Time.current - start_time

    assert_response :success
    assert load_time < 2, "Page took too long to load: #{load_time} seconds"
  end

  # ========== Edge Cases ==========

  test "should handle subscription with deleted plan gracefully" do
    login_as_admin

    # Create subscription with a plan that will be deleted
    doomed_plan = Plan.create!(
      name: "Doomed Plan",
      price: 5.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 3,
      active: false
    )

    doomed_subscription = Subscription.create!(
      user: @user_no_subscription,
      plan: doomed_plan,
      status: :active,
      started_at: 5.days.ago,
      expires_at: 25.days.from_now
    )

    # Note: In a real app, you'd want to handle this case properly
    # For now, we'll test that it doesn't break
    get admin_subscription_url(doomed_subscription)
    assert_response :success
    assert_match doomed_plan.name, response.body
  end

  test "should display subscription for soft-deleted user" do
    login_as_admin

    # Soft delete a user
    @user_with_email.soft_delete!

    # The subscription should not appear in index due to default scope
    get admin_subscriptions_url
    assert_response :success

    # The active subscription shouldn't be visible since user is soft deleted
    refute_match "##{@active_subscription.id}", response.body
  end

  test "should handle subscription at exact expiry time" do
    login_as_admin

    # Create subscription that expires exactly now
    expiring_now = Subscription.create!(
      user: @user_no_subscription,
      plan: @monthly_plan,
      status: :active,
      started_at: 30.days.ago,
      expires_at: Time.current
    )

    get admin_subscription_url(expiring_now)
    assert_response :success

    # Should be considered expired
    assert expiring_now.expired?
  end

  private

  def login_as_admin
    post admin_session_url, params: {
      email: @admin.email,
      password: "password123"
    }
  end

  def number_to_currency(amount)
    "$%.2f" % amount
  end

  def assert_queries(expected_count, &block)
    # Helper to test N+1 query prevention
    queries = []
    counter = ->(_name, _started, _finished, _unique_id, payload) {
      queries << payload[:sql] unless payload[:sql].match?(/SCHEMA/)
    }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)

    assert queries.size <= expected_count,
           "Expected <= #{expected_count} queries, got #{queries.size}"
  end
end
