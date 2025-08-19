require "test_helper"

class PlansControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email_address: "test@example.com", password: "password")
    @passphrase = @user.instance_variable_get(:@issued_passphrase)
    @plan = Plan.create!(
      name: "Test Plan",
      description: "Test description",
      price: 9.99,
      currency: "USD",
      duration_days: 30,
      active: true,
      features: [ "Feature 1", "Feature 2" ]
    )
    @inactive_plan = Plan.create!(
      name: "Inactive Plan",
      price: 19.99,
      duration_days: 60,
      active: false
    )
  end

  def sign_in_user
    post session_path, params: { passphrase: "#{@passphrase}:password" }
  end

  test "should get index" do
    get plans_path
    assert_response :success
    assert_select "h2", "VPN Subscription Plans"
    # Check that only active plan is shown
    assert_match @plan.name, response.body
  end

  test "should show active plans only" do
    get plans_path
    assert_response :success
    assert_match @plan.name, response.body
    assert_no_match @inactive_plan.name, response.body
  end

  test "should get show" do
    sign_in_user
    get plan_path(@plan)
    assert_response :success
    assert_select "h3", @plan.name
    assert_match @plan.description, response.body
  end

  test "should display plan features" do
    sign_in_user
    get plan_path(@plan)
    @plan.features.each do |feature|
      assert_match feature, response.body
    end
  end

  test "should display available cryptocurrencies" do
    sign_in_user
    mock_cryptos = {
      "btc" => { "name" => "Bitcoin" },
      "eth" => { "name" => "Ethereum" }
    }

    PaymentProcessor.stubs(:available_cryptos).returns(mock_cryptos)

    get plan_path(@plan)
    assert_response :success
    assert_match "BTC", response.body
    assert_match "ETH", response.body
  end

  test "should handle no available cryptocurrencies" do
    sign_in_user
    PaymentProcessor.stubs(:available_cryptos).returns({})

    get plan_path(@plan)
    assert_response :success
    assert_match "Payment methods are temporarily unavailable", response.body
  end

  test "should redirect to login when not authenticated for show" do
    # Don't sign in
    get plan_path(@plan)
    assert_redirected_to new_session_path
  end

  test "should show 404 for inactive plan" do
    sign_in_user
    # The controller finds only active plans, so this should return 404
    get plan_path(@inactive_plan)
    assert_response :not_found
  end
end
