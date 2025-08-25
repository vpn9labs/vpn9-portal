require "net/http"
require "json"
require "uri"

#
# BitcartClient is a minimal HTTP client for interacting with the Bitcart API.
#
# Responsibilities
# - Discover supported cryptocurrencies and stores
# - Create invoices for a given store/plan/payment
# - Query invoices and exchange rates
# - Normalize responses and raise meaningful errors on failures
#
# Configuration
# - Base URL: `BITCART_BASE_URL` (e.g., https://bitcart.example.com)
# - API key:  `BITCART_API_KEY`   (Bearer token)
# - Optional store id: `BITCART_STORE_ID` (otherwise the first store is used)
#
# Error handling
# - Raises ApiError for non‑2xx responses with descriptive messages
# - Raises ConnectionError for timeouts/connection issues
# - Logs and returns empty arrays for read‑style helpers on error
#
# Usage
#   client = BitcartClient.new
#   invoice = client.create_invoice(amount: 9.99, currency: "USD", external_id: payment.id)
#   details = client.get_invoice(invoice["id"])
#
class BitcartClient
  class Error < StandardError; end
  class ApiError < Error; end
  class ConnectionError < Error; end

  attr_reader :base_url, :api_key

  # Initialize a new client.
  #
  # @param base_url [String, nil] Bitcart base URL (falls back to ENV or http://localhost:8091)
  # @param api_key  [String, nil] API key (falls back to ENV or a test placeholder)
  def initialize(base_url: nil, api_key: nil)
    @base_url = base_url || ENV["BITCART_BASE_URL"] || "http://localhost:8091"
    @api_key = api_key || ENV["BITCART_API_KEY"] || "test-api-key"
  end

  # Get available cryptocurrencies
  # @return [Array<Hash>] list of cryptos (raw records from API)
  def available_cryptos
    response = get("/cryptos")
    # Handle paginated response format
    if response.is_a?(Hash) && response["result"]
      response["result"]
    else
      response
    end
  rescue => e
    Rails.logger.error "Failed to fetch cryptocurrencies from Bitcart: #{e.message}"
    []
  end

  # Get stores
  # @return [Array<Hash>] list of stores (raw records from API)
  def get_stores
    response = get("/stores")
    # Handle paginated response format
    if response.is_a?(Hash) && response["result"]
      response["result"]
    else
      response
    end
  rescue => e
    Rails.logger.error "Failed to fetch stores from Bitcart: #{e.message}"
    []
  end

  # Create an invoice
  #
  # @param params [Hash]
  # @option params [Numeric,String] :amount        Amount in fiat currency
  # @option params [String]         :currency      Fiat currency (default: "USD")
  # @option params [String]         :external_id   External order/payment id
  # @option params [String]         :callback_url  Webhook URL to receive status updates
  # @option params [String]         :redirect_url  URL to redirect customer after payment
  # @option params [String]         :email         Buyer email (optional)
  # @option params [String]         :crypto        Preferred crypto symbol (e.g., "btc")
  # @option params [String]         :store_id      Explicit store id (falls back to BITCART_STORE_ID or first store)
  # @return [Hash] raw invoice payload returned by Bitcart
  # @raise [ApiError, ConnectionError]
  def create_invoice(params = {})
    # Get the first available store if store_id not provided
    store_id = params[:store_id] || ENV["BITCART_STORE_ID"] || get_default_store_id

    invoice_params = {
      store_id: store_id,
      price: params[:amount].to_s,
      currency: params[:currency] || "USD",
      order_id: params[:external_id],
      notification_url: params[:callback_url],
      redirect_url: params[:redirect_url],
      buyer_email: params[:email]
    }

    # If a specific crypto is requested, set it in the promoted field
    if params[:crypto]
      invoice_params[:promoted] = params[:crypto].downcase
    end

    response = post("/invoices", invoice_params.compact)
    Rails.logger.info "Bitcart raw invoice response: #{response.inspect}"
    response
  end

  # Get invoice details
  # @param invoice_id [String]
  # @return [Hash]
  # @raise [ApiError, ConnectionError]
  def get_invoice(invoice_id)
    get("/invoices/#{invoice_id}")
  end

  # Get rate for a specific cryptocurrency
  # @param crypto [String] crypto symbol (e.g., "btc")
  # @param fiat [String]   fiat currency (default: "USD")
  # @return [Hash]
  # @raise [ApiError, ConnectionError]
  def get_rate(crypto, fiat = "USD")
    get("/rates", { crypto: crypto, fiat: fiat })
  end

  private

  # Resolve a default store id by querying /stores.
  # @return [String]
  # @raise [ApiError] when no stores are available
  def get_default_store_id
    stores = get_stores
    if stores.is_a?(Array) && stores.any?
      stores.first["id"]
    else
      raise ApiError, "No stores available in Bitcart"
    end
  end

  # Perform a GET request to a Bitcart API path.
  # @api private
  def get(path, params = {})
    uri = build_uri("#{@base_url}/api#{path}", params)
    request = Net::HTTP::Get.new(uri)
    execute_request(request)
  end

  # Perform a POST request to a Bitcart API path with a JSON body.
  # @api private
  def post(path, body = {})
    uri = URI("#{@base_url}/api#{path}")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = body.to_json
    execute_request(request)
  end

  # Build a URI with optional query params.
  # @api private
  def build_uri(url, params = {})
    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params.any?
    uri
  end

  # Execute an HTTP request with timeouts and error handling.
  # @api private
  def execute_request(request)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Accept"] = "application/json"

    uri = URI(request.uri)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 30
    http.open_timeout = 30

    begin
      response = http.request(request)
      handle_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise ConnectionError, "Request timed out: #{e.message}"
    rescue => e
      raise ConnectionError, "Connection failed: #{e.message}"
    end
  end

  # Parse and normalize a Net::HTTP response.
  # Raises ApiError for non‑2xx status codes with a helpful message.
  # @api private
  def handle_response(response)
    body = response.body

    begin
      data = JSON.parse(body) if body.present?
    rescue JSON::ParserError
      data = { error: body }
    end

    case response.code.to_i
    when 200..299
      data
    when 400
      raise ApiError, "Bad request: #{data['detail'] || data['error'] || 'Invalid request'}"
    when 401
      raise ApiError, "Unauthorized: Invalid API key"
    when 404
      raise ApiError, "Not found: #{data['detail'] || data['error'] || 'Resource not found'}"
    when 422
      raise ApiError, "Validation error: #{data['detail'] || data['error'] || 'Invalid data'}"
    when 500..599
      raise ApiError, "Server error: #{data['detail'] || data['error'] || 'Internal server error'}"
    else
      raise ApiError, "Unexpected response (#{response.code}): #{body}"
    end
  end
end
