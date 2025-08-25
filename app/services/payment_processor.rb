#
# PaymentProcessor is a thin façade over concrete payment backends.
#
# Current backend: Bitcart (ENV: `PAYMENT_PROCESSOR=bitcart`).
# It provides a stable API for the app to:
# - discover available cryptos
# - create a payment/invoice for a plan
# - query payment status
#
# Environment
# - PAYMENT_PROCESSOR: backend selector (default: "bitcart")
# - WEBHOOK_HOST: public host used to construct webhook URL callbacks
# - BITCART_BASE_URL / BITCART_API_KEY / BITCART_STORE_ID: delegated to BitcartClient
#
class PaymentProcessor
  class << self
    # Return a configured client instance for the selected processor.
    # @return [Object] currently an instance of BitcartClient
    def client
      case processor_type
      when :bitcart
        BitcartClient.new
      else
        raise "Unknown payment processor: #{processor_type}"
      end
    end

    # List of cryptocurrencies supported by the processor.
    #
    # For Bitcart, returns a hash keyed by symbol with simple metadata:
    # { "btc" => { "name" => "BTC", "enabled" => true }, ... }
    #
    # @return [Hash{String=>Hash}]
    def available_cryptos
      case processor_type
      when :bitcart
        # Bitcart returns an array of crypto symbols
        result = client.available_cryptos
        # Convert to hash format for consistency
        Hash[result.map { |crypto| [ crypto.downcase, { "name" => crypto.upcase, "enabled" => true } ] }]
      else
        {}
      end
    rescue => e
      Rails.logger.error "Failed to fetch cryptocurrencies: #{e.message}"
      {}
    end

    # Create a new payment/invoice with the processor for the specified crypto.
    #
    # Side effects:
    # - Generates and persists a webhook secret on the Payment
    # - Constructs a processor‑specific invoice and returns normalized details
    #
    # @param crypto [String] crypto symbol requested (e.g., "btc")
    # @param payment [Payment] payment model (amount/currency/expires etc.)
    # @param plan [Plan] plan being purchased (not used directly by Bitcart)
    # @return [Hash] normalized invoice data with keys: "id", "wallet", "amount", "actual_currency", "is_token"
    # @raise [RuntimeError] for unknown processors
    def create_payment(crypto, payment, plan)
      case processor_type
      when :bitcart
        payment.generate_webhook_secret!
        response = client.create_invoice(
          amount: payment.amount,
          currency: payment.currency,
          external_id: payment.id.to_s,
          callback_url: Rails.application.routes.url_helpers.webhook_payments_url(host: webhook_host, secret: payment.webhook_secret),
          crypto: crypto.upcase
        )

        Rails.logger.info "Bitcart invoice response: #{response.inspect}"

        # Extract payment details from Bitcart response
        # Bitcart returns payment methods in a "payments" array
        payments = response["payments"] || []

        # Find the payment method for the requested cryptocurrency
        payment_method = payments.find { |pm| pm["currency"].downcase == crypto.downcase }

        if payment_method
          {
            "id" => response["id"],
            "wallet" => payment_method["payment_address"],
            "amount" => payment_method["amount"],
            "actual_currency" => payment_method["symbol"] || crypto,
            "is_token" => payment_method["contract"].present?
          }
        else
          # Fallback if no matching payment method found
          Rails.logger.error "No payment method found for #{crypto} in Bitcart response"
          {
            "id" => response["id"],
            "wallet" => nil,
            "amount" => response["price"]
          }
        end
      else
        raise "Unknown payment processor: #{processor_type}"
      end
    end

    # Query payment/invoice status from the processor and map to normalized states.
    #
    # @param crypto [String] crypto symbol (may be unused by some processors)
    # @param payment_id [String] processor invoice id
    # @return [Hash] e.g., { "status" => "PAID"|"UNPAID"|"EXPIRED"|"FAILED", "amount_received" => Numeric }
    # @raise [RuntimeError] for unknown processors
    def get_payment_status(crypto, payment_id)
      case processor_type
      when :bitcart
        invoice = client.get_invoice(payment_id)
        {
          "status" => map_bitcart_status(invoice["status"]),
          "amount_received" => invoice["received_amount"]
        }
      else
        raise "Unknown payment processor: #{processor_type}"
      end
    end

    private

    # Selected processor symbol (e.g., :bitcart)
    # @return [Symbol]
    def processor_type
      @processor_type ||= (ENV["PAYMENT_PROCESSOR"] || "bitcart").to_sym
    end

    # Public host for webhook callback URLs
    # @return [String]
    def webhook_host
      ENV["WEBHOOK_HOST"] || "localhost:3000"
    end

    # Map Bitcart invoice status to normalized app status
    # @param status [String]
    # @return [String]
    def map_bitcart_status(status)
      case status
      when "new", "pending"
        "UNPAID"
      when "paid", "confirmed", "complete"
        "PAID"
      when "expired"
        "EXPIRED"
      when "invalid"
        "FAILED"
      else
        status.upcase
      end
    end
  end
end
