require "test_helper"

class PaymentProcessorTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @plan = plans(:monthly)
    @payment = Payment.create!(user: @user, plan: @plan, amount: 9.99, currency: "USD", status: :pending)
    @original_processor = ENV["PAYMENT_PROCESSOR"]
    ENV["PAYMENT_PROCESSOR"] = "bitcart"
    @original_webhook_host = ENV["WEBHOOK_HOST"]
    ENV["WEBHOOK_HOST"] = "example.com"
  end

  def teardown
    ENV["PAYMENT_PROCESSOR"] = @original_processor
    ENV["WEBHOOK_HOST"] = @original_webhook_host
  end

  test "available_cryptos normalizes bitcart symbols" do
    fake = mock
    fake.stubs(:available_cryptos).returns([ "BTC", "ETH" ])
    PaymentProcessor.stubs(:client).returns(fake)

    result = PaymentProcessor.available_cryptos
    assert_equal({
      "btc" => { "name" => "BTC", "enabled" => true },
      "eth" => { "name" => "ETH", "enabled" => true }
    }, result)
  end

  test "available_cryptos returns empty hash on error" do
    fake = mock
    fake.stubs(:available_cryptos).raises(StandardError.new("boom"))
    PaymentProcessor.stubs(:client).returns(fake)

    result = PaymentProcessor.available_cryptos
    assert_equal({}, result)
  end

  test "create_payment generates webhook secret and normalizes invoice with matching method" do
    response = {
      "id" => "inv123",
      "payments" => [
        { "currency" => "BTC", "payment_address" => "bc1qabc", "amount" => "0.0002", "symbol" => "BTC" },
        { "currency" => "ETH", "payment_address" => "0xdef", "amount" => "0.01", "symbol" => "ETH" }
      ],
      "price" => "9.99"
    }

    fake = mock
    fake.stubs(:create_invoice).returns(response)
    PaymentProcessor.stubs(:client).returns(fake)

    @payment.expects(:generate_webhook_secret!).once

    result = PaymentProcessor.create_payment("btc", @payment, @plan)

    assert_equal "inv123", result["id"]
    assert_equal "bc1qabc", result["wallet"]
    assert_equal "0.0002", result["amount"]
    assert_equal "BTC", result["actual_currency"]
    assert_equal false, result["is_token"]
  end

  test "create_payment falls back when no matching payment method" do
    response = {
      "id" => "inv999",
      "payments" => [ { "currency" => "LTC", "payment_address" => "ltc1xyz", "amount" => "1.0" } ],
      "price" => "9.99"
    }

    fake = mock
    fake.stubs(:create_invoice).returns(response)
    PaymentProcessor.stubs(:client).returns(fake)
    @payment.stubs(:generate_webhook_secret!)

    result = PaymentProcessor.create_payment("btc", @payment, @plan)

    assert_equal "inv999", result["id"]
    assert_nil result["wallet"]
    assert_equal "9.99", result["amount"]
  end

  test "get_payment_status maps bitcart statuses" do
    fake = mock
    fake.stubs(:get_invoice).returns({ "status" => "new", "received_amount" => 0 })
    PaymentProcessor.stubs(:client).returns(fake)
    r = PaymentProcessor.get_payment_status("btc", "id1")
    assert_equal "UNPAID", r["status"]

    fake2 = mock
    fake2.stubs(:get_invoice).returns({ "status" => "paid", "received_amount" => 1.23 })
    PaymentProcessor.stubs(:client).returns(fake2)
    r2 = PaymentProcessor.get_payment_status("btc", "id2")
    assert_equal "PAID", r2["status"]

    fake3 = mock
    fake3.stubs(:get_invoice).returns({ "status" => "expired", "received_amount" => 0 })
    PaymentProcessor.stubs(:client).returns(fake3)
    r3 = PaymentProcessor.get_payment_status("btc", "id3")
    assert_equal "EXPIRED", r3["status"]

    fake4 = mock
    fake4.stubs(:get_invoice).returns({ "status" => "invalid", "received_amount" => 0 })
    PaymentProcessor.stubs(:client).returns(fake4)
    r4 = PaymentProcessor.get_payment_status("btc", "id4")
    assert_equal "FAILED", r4["status"]
  end

  test "unknown processor raises on create and status" do
    ENV["PAYMENT_PROCESSOR"] = "unknown"
    assert_raises RuntimeError do
      PaymentProcessor.create_payment("btc", @payment, @plan)
    end
    assert_raises RuntimeError do
      PaymentProcessor.get_payment_status("btc", "id")
    end
  end
end
