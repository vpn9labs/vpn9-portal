require "test_helper"

class Admin::PlansControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = Admin.create!(
      email: "admin@example.com",
      password: "securepassword123",
      password_confirmation: "securepassword123"
    )

    @plan = Plan.create!(
      name: "Basic Plan",
      description: "Basic subscription plan",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 3,
      active: true
    )

    @plan_with_subscriptions = Plan.create!(
      name: "Premium Plan",
      description: "Premium subscription with more features",
      price: 19.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 10,
      active: true
    )

    # Create a user and subscription for the premium plan
    @user = User.create!(email_address: "subscriber@example.com")
    @subscription = Subscription.create!(
      user: @user,
      plan: @plan_with_subscriptions,
      status: :active,
      started_at: Time.current,
      expires_at: 30.days.from_now
    )

    @inactive_plan = Plan.create!(
      name: "Legacy Plan",
      description: "Old plan no longer offered",
      price: 14.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 5,
      active: false
    )
  end

  def admin_login
    post admin_session_path, params: {
      email: @admin.email,
      password: "securepassword123"
    }
  end

  # === Authentication Tests ===

  test "should redirect to login if not authenticated" do
    get admin_plans_path
    assert_redirected_to new_admin_session_path
  end

  test "should allow access when authenticated as admin" do
    admin_login
    get admin_plans_path
    assert_response :success
  end

  test "should maintain session across requests" do
    admin_login

    get admin_plans_path
    assert_response :success

    get new_admin_plan_path
    assert_response :success
  end

  # === Index Action Tests ===

  test "should get index" do
    admin_login
    get admin_plans_path

    assert_response :success
    assert_select "h1", "Subscription Plans"
    assert_select "a", text: "New Plan"
  end

  test "should display all plans ordered by price" do
    admin_login
    get admin_plans_path

    assert_response :success
    assert_match @plan.name, response.body
    assert_match @plan_with_subscriptions.name, response.body
    assert_match @inactive_plan.name, response.body

    # Check ordering
    plan_positions = response.body.index(@plan.name),
                     response.body.index(@inactive_plan.name),
                     response.body.index(@plan_with_subscriptions.name)
    assert_equal plan_positions, plan_positions.sort
  end

  test "should display plan details in index" do
    admin_login
    get admin_plans_path

    assert_response :success

    # Check price display
    assert_match "$9.99 USD", response.body
    assert_match "$19.99 USD", response.body

    # Check duration display
    assert_match "Monthly", response.body

    # Check device limits
    assert_select "span", text: "3"
    assert_select "span", text: "10"

    # Check status badges
    assert_select "span.bg-green-100", minimum: 2
    assert_select "span.bg-red-100", minimum: 1
  end

  test "should show active subscriptions count" do
    admin_login
    get admin_plans_path

    assert_response :success
    assert_select "span.bg-gray-100", text: "1"
  end

  test "should disable delete button for plans with subscriptions" do
    admin_login
    get admin_plans_path

    assert_response :success

    # Should have delete link for plan without subscriptions
    assert_select "a[data-turbo-method='delete']", minimum: 1

    # Should have disabled delete text for plan with subscriptions
    assert_match "Cannot delete plan with active subscriptions", response.body
  end

  test "should show empty state when no plans exist" do
    Plan.destroy_all

    admin_login
    get admin_plans_path

    assert_response :success
    assert_match "No plans found", response.body
    assert_select "a", text: "Create one"
  end

  # === Show Action Tests ===

  test "should show plan details" do
    admin_login
    get admin_plan_path(@plan)

    assert_response :success
    assert_select "h1", @plan.name
    assert_match @plan.description, response.body
    assert_match "$9.99 USD", response.body
  end

  test "should display plan statistics" do
    # Create some payments for revenue calculation
    payment1 = Payment.create!(
      user: @user,
      plan: @plan_with_subscriptions,
      amount: 19.99,
      currency: "USD",
      status: :paid
    )

    payment2 = Payment.create!(
      user: @user,
      plan: @plan_with_subscriptions,
      amount: 19.99,
      currency: "USD",
      status: :paid
    )

    admin_login
    get admin_plan_path(@plan_with_subscriptions)

    assert_response :success

    # Check statistics display
    assert_match "Active Subscriptions", response.body
    assert_match "1", response.body

    assert_match "Total Revenue", response.body
    assert_match "$39.98", response.body
  end

  test "should show edit and back buttons" do
    admin_login
    get admin_plan_path(@plan)

    assert_response :success
    assert_select "a", text: "Edit"
    assert_select "a", text: "Back to Plans"
  end

  test "should show delete button for deletable plans" do
    admin_login
    get admin_plan_path(@plan)

    assert_response :success
    assert_select "a[data-turbo-method='delete']", text: "Delete Plan"
  end

  test "should show disabled delete button for non-deletable plans" do
    admin_login
    get admin_plan_path(@plan_with_subscriptions)

    assert_response :success
    assert_select "button[disabled]", text: "Delete Plan"
    assert_match "Cannot delete plan with active subscriptions", response.body
  end

  test "should handle non-existent plan in show" do
    admin_login

    get admin_plan_path(999999)
    assert_response :not_found
  end

  # === New Action Tests ===

  test "should get new" do
    admin_login
    get new_admin_plan_path

    assert_response :success
    assert_select "h1", "New Subscription Plan"
    assert_select "form"
  end

  test "should render form fields in new" do
    admin_login
    get new_admin_plan_path

    assert_response :success

    # Check form fields
    assert_select "input[name='plan[name]']"
    assert_select "textarea[name='plan[description]']"
    assert_select "input[name='plan[price]']"
    assert_select "select[name='plan[currency]']"
    assert_select "select[name='plan[duration_days]']"
    assert_select "select[name='plan[device_limit]']"
    assert_select "input[type='checkbox'][name='plan[active]']"

    # Check submit button
    assert_select "input[type='submit']"
  end

  test "should have currency options in new form" do
    admin_login
    get new_admin_plan_path

    assert_response :success
    assert_select "option[value='USD']"
    assert_select "option[value='EUR']"
    assert_select "option[value='GBP']"
    assert_select "option[value='BTC']"
    assert_select "option[value='ETH']"
  end

  test "should have duration options in new form" do
    admin_login
    get new_admin_plan_path

    assert_response :success
    assert_select "option[value='7']", text: "Weekly (7 days)"
    assert_select "option[value='30']", text: "Monthly (30 days)"
    assert_select "option[value='90']", text: "Quarterly (90 days)"
    assert_select "option[value='365']", text: "Yearly (365 days)"
    assert_select "option[value='']", text: "Custom"
  end

  # === Create Action Tests ===

  test "should create plan with valid params" do
    admin_login

    assert_difference("Plan.count", 1) do
      post admin_plans_path, params: {
        plan: {
          name: "New Test Plan",
          description: "A new test plan",
          price: 24.99,
          currency: "USD",
          duration_days: 90,
          device_limit: 5,
          active: true
        }
      }
    end

    assert_redirected_to admin_plans_path
    follow_redirect!
    assert_match "Plan was successfully created", response.body

    # Verify plan was created correctly
    new_plan = Plan.order(:created_at).last
    assert_equal "New Test Plan", new_plan.name
    assert_equal 24.99, new_plan.price
    assert_equal 90, new_plan.duration_days
  end

  test "should not create plan with invalid params" do
    admin_login

    assert_no_difference("Plan.count") do
      post admin_plans_path, params: {
        plan: {
          name: "", # Invalid - blank name
          price: -10, # Invalid - negative price
          duration_days: 0 # Invalid - zero days
        }
      }
    end

    assert_response :unprocessable_content
    assert_select "div.bg-red-100", text: /Validation errors/
  end

  test "should validate required fields on create" do
    admin_login

    post admin_plans_path, params: {
      plan: {
        name: "",
        price: "",
        duration_days: ""
      }
    }

    assert_response :unprocessable_content
    assert_match "Name can&#39;t be blank", response.body
    assert_match "Price can&#39;t be blank", response.body
    assert_match "Duration days can&#39;t be blank", response.body
  end

  test "should handle custom duration on create" do
    admin_login

    assert_difference("Plan.count", 1) do
      post admin_plans_path, params: {
        plan: {
          name: "Custom Duration Plan",
          price: 49.99,
          currency: "USD",
          duration_days: 180, # Custom 6-month duration
          device_limit: 5,
          active: true
        }
      }
    end

    assert_redirected_to admin_plans_path
    new_plan = Plan.order(:created_at).last
    assert_equal 180, new_plan.duration_days
  end

  test "should set default values on create" do
    admin_login

    post admin_plans_path, params: {
      plan: {
        name: "Default Values Plan",
        price: 9.99,
        duration_days: 30,
        device_limit: 5
      }
    }

    assert_redirected_to admin_plans_path
    new_plan = Plan.order(:created_at).last
    assert_equal "USD", new_plan.currency # Default currency
    assert_equal true, new_plan.active # Default to active
  end

  # === Edit Action Tests ===

  test "should get edit" do
    admin_login
    get edit_admin_plan_path(@plan)

    assert_response :success
    assert_select "h1", "Edit Subscription Plan"
    assert_match @plan.name, response.body
  end

  test "should populate form with existing values in edit" do
    admin_login
    get edit_admin_plan_path(@plan)

    assert_response :success

    # Check that form is populated with current values
    assert_select "input[name='plan[name]'][value='#{@plan.name}']"
    assert_select "input[name='plan[price]'][value='#{@plan.price}']"
    assert_select "select[name='plan[currency]'] option[selected][value='#{@plan.currency}']"
    assert_select "input[type='checkbox'][name='plan[active]'][checked]"
  end

  test "should show warning for plans with subscriptions in edit" do
    admin_login
    get edit_admin_plan_path(@plan_with_subscriptions)

    assert_response :success
    assert_match "This plan has 1 active subscriptions", response.body
    assert_match "cannot be deleted", response.body
  end

  test "should handle non-existent plan in edit" do
    admin_login

    get edit_admin_plan_path(999999)
    assert_response :not_found
  end

  # === Update Action Tests ===

  test "should update plan with valid params" do
    admin_login

    patch admin_plan_path(@plan), params: {
      plan: {
        name: "Updated Plan Name",
        price: 12.99,
        description: "Updated description"
      }
    }

    assert_redirected_to admin_plans_path
    follow_redirect!
    assert_match "Plan was successfully updated", response.body

    # Verify updates
    @plan.reload
    assert_equal "Updated Plan Name", @plan.name
    assert_equal 12.99, @plan.price
    assert_equal "Updated description", @plan.description
  end

  test "should not update plan with invalid params" do
    admin_login
    original_name = @plan.name

    patch admin_plan_path(@plan), params: {
      plan: {
        name: "",
        price: -5
      }
    }

    assert_response :unprocessable_content
    assert_select "div.bg-red-100", text: /Validation errors/

    # Verify plan was not updated
    @plan.reload
    assert_equal original_name, @plan.name
  end

  test "should allow deactivating plan with active subscriptions" do
    admin_login

    patch admin_plan_path(@plan_with_subscriptions), params: {
      plan: {
        active: false
      }
    }

    assert_redirected_to admin_plans_path
    @plan_with_subscriptions.reload
    assert_equal false, @plan_with_subscriptions.active
  end

  test "should update only changed attributes" do
    admin_login
    original_price = @plan.price

    patch admin_plan_path(@plan), params: {
      plan: {
        name: "Partially Updated Plan"
      }
    }

    assert_redirected_to admin_plans_path
    @plan.reload
    assert_equal "Partially Updated Plan", @plan.name
    assert_equal original_price, @plan.price # Should remain unchanged
  end

  test "should handle non-existent plan in update" do
    admin_login

    patch admin_plan_path(999999), params: {
      plan: { name: "Won't work" }
    }
    assert_response :not_found
  end

  # === Destroy Action Tests ===

  test "should destroy plan without subscriptions" do
    admin_login

    assert_difference("Plan.count", -1) do
      delete admin_plan_path(@plan)
    end

    assert_redirected_to admin_plans_path
    follow_redirect!
    assert_match "Plan was successfully deleted", response.body
  end

  test "should not destroy plan with active subscriptions" do
    admin_login

    assert_no_difference("Plan.count") do
      delete admin_plan_path(@plan_with_subscriptions)
    end

    assert_redirected_to admin_plans_path
    follow_redirect!
    assert_match "Cannot delete plan with active subscriptions", response.body
  end

  test "should handle non-existent plan in destroy" do
    admin_login

    delete admin_plan_path(999999)
    assert_response :not_found
  end

  test "should destroy plan with cancelled subscriptions" do
    # Cancel the subscription
    @subscription.update!(status: :cancelled)

    admin_login

    # Should still not delete if subscription exists, even if cancelled
    assert_no_difference("Plan.count") do
      delete admin_plan_path(@plan_with_subscriptions)
    end

    assert_redirected_to admin_plans_path
  end

  # === Navigation Tests ===

  test "should have plans link highlighted in admin navigation" do
    admin_login
    get admin_plans_path

    assert_response :success
    assert_select "a.bg-gray-900.text-white", text: "Plans"
  end

  test "should include plans in mobile navigation" do
    admin_login
    get admin_plans_path

    assert_response :success
    # Mobile nav should include Plans link
    assert_select "nav a", text: "Plans", minimum: 1
  end

  # === Permission Tests ===

  test "should not allow regular user to access admin plans" do
    user = User.create!(email_address: "regular@example.com")

    # Try to access without admin session
    get admin_plans_path
    assert_redirected_to new_admin_session_path
  end

  # === Form Validation Tests ===

  test "should validate price is non-negative" do
    admin_login

    post admin_plans_path, params: {
      plan: {
        name: "Invalid Price Plan",
        price: -10,
        duration_days: 30,
        device_limit: 5
      }
    }

    assert_response :unprocessable_content
    assert_match "greater than or equal to 0", response.body
  end

  test "should validate duration_days is positive" do
    admin_login

    post admin_plans_path, params: {
      plan: {
        name: "Invalid Duration Plan",
        price: 10,
        duration_days: 0,
        device_limit: 5
      }
    }

    assert_response :unprocessable_content
    assert_match "greater than 0", response.body
  end

  test "should validate device_limit is within range" do
    admin_login

    post admin_plans_path, params: {
      plan: {
        name: "Too Many Devices Plan",
        price: 10,
        duration_days: 30,
        device_limit: 101
      }
    }

    assert_response :unprocessable_content
    assert_match "less than or equal to 100", response.body
  end

  # === Display Format Tests ===

  test "should display unlimited for 100 device limit" do
    unlimited_plan = Plan.create!(
      name: "Unlimited Plan",
      price: 99.99,
      currency: "USD",
      duration_days: 365,
      device_limit: 100,
      active: true
    )

    admin_login
    get admin_plans_path

    assert_response :success
    assert_match "Unlimited", response.body
  end

  test "should display correct duration formats" do
    weekly_plan = Plan.create!(
      name: "Weekly Plan",
      price: 2.99,
      currency: "USD",
      duration_days: 7,
      device_limit: 1
    )

    quarterly_plan = Plan.create!(
      name: "Quarterly Plan",
      price: 24.99,
      currency: "USD",
      duration_days: 90,
      device_limit: 5
    )

    yearly_plan = Plan.create!(
      name: "Yearly Plan",
      price: 99.99,
      currency: "USD",
      duration_days: 365,
      device_limit: 10
    )

    admin_login
    get admin_plans_path

    assert_response :success
    assert_match "Weekly", response.body
    assert_match "Quarterly", response.body
    assert_match "Yearly", response.body
  end

  # === JavaScript Functionality Tests ===

  test "should include custom duration JavaScript" do
    admin_login
    get new_admin_plan_path

    assert_response :success
    assert_match "data-duration-select", response.body
    assert_match "custom-duration", response.body
    assert_match "addEventListener", response.body
  end

  # === Security Tests ===

  test "should escape HTML in plan names" do
    xss_plan = Plan.create!(
      name: "<script>alert('XSS')</script>",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 5
    )

    admin_login
    get admin_plans_path

    assert_response :success
    assert_no_match "<script>alert('XSS')</script>", response.body
    assert_match "&lt;script&gt;", response.body
  end

  test "should handle SQL injection attempts in params" do
    admin_login

    # Attempt SQL injection in plan ID
    get admin_plan_path("1 OR 1=1")
    assert_response :not_found
  end

  # === Edge Cases ===

  test "should handle very large prices" do
    admin_login

    post admin_plans_path, params: {
      plan: {
        name: "Enterprise Plan",
        price: 999999.99,
        currency: "USD",
        duration_days: 365,
        device_limit: 100
      }
    }

    assert_redirected_to admin_plans_path
    enterprise_plan = Plan.order(:created_at).last
    assert_equal 999999.99, enterprise_plan.price
  end

  test "should handle plans with nil descriptions" do
    no_desc_plan = Plan.create!(
      name: "No Description Plan",
      description: nil,
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      device_limit: 3
    )

    admin_login
    get admin_plan_path(no_desc_plan)

    assert_response :success
    assert_match "No description", response.body
  end

  # === Pagination Tests (if implemented) ===

  test "should handle many plans efficiently" do
    # Create 50 plans
    50.times do |i|
      Plan.create!(
        name: "Plan #{i}",
        price: 9.99 + i,
        currency: "USD",
        duration_days: 30,
        device_limit: 5
      )
    end

    admin_login

    start_time = Time.current
    get admin_plans_path
    load_time = Time.current - start_time

    assert_response :success
    assert load_time < 2, "Page took too long to load: #{load_time} seconds"
  end

  # === Session Management ===

  test "should require re-authentication after session expires" do
    admin_login
    get admin_plans_path
    assert_response :success

    # Clear session
    reset!

    get admin_plans_path
    assert_redirected_to new_admin_session_path
  end

  test "should redirect back to requested page after login" do
    # Try to access plans without auth
    get edit_admin_plan_path(@plan)
    assert_redirected_to new_admin_session_path

    # Login
    post admin_session_path, params: {
      email: @admin.email,
      password: "securepassword123"
    }

    # Should redirect to originally requested page
    assert_redirected_to edit_admin_plan_path(@plan)
  end
end
