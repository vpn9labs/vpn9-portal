class PaymentProcessor
  class << self
    def client
      case processor_type
      when :bitcart
        BitcartClient.new
      else
        raise "Unknown payment processor: #{processor_type}"
      end
    end

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

    def processor_type
      @processor_type ||= (ENV["PAYMENT_PROCESSOR"] || "bitcart").to_sym
    end

    def webhook_host
      ENV["WEBHOOK_HOST"] || "localhost:3000"
    end

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
