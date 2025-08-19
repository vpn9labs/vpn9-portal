class Api::V1::DnsLeakTestController < Api::BaseController
  skip_before_action :authenticate!

  DNS_LEAK_SERVICE_URL = Rails.env.production? ?
    "https://api.dnsleak.vpn9.com" :
    "http://localhost:8080"

  def show
    # Create DNS leak test via external service
    client_ip = request.remote_ip

    payload = {
      test_domains: [ "example.com" ],  # Use a minimal test domain
      timeout_seconds: 30,
      enable_ipv6: true,
      enable_canary: true,
      num_canary_domains: 5
    }

    response = make_external_request(
      :post,
      "#{DNS_LEAK_SERVICE_URL}/api/v1/test",
      payload
    )

    if response[:success]
      test_data = response[:data]

      canary_domains = test_data["canary_domains"] || []
      test_domains = test_data["test_domains"] || []
      all_domains = canary_domains + test_domains

      render json: {
        test_id: test_data["test_id"],
        domains: all_domains,
        client_ip: client_ip,
        status: test_data["status"],
        instructions: {
          step1: "Make DNS queries to the provided domains",
          step2: "Wait for test completion (timeout: #{payload[:timeout_seconds]}s)",
          step3: "Check results by calling GET /api/v1/dns_leak_test/results with test_id parameter"
        }
      }
    else
      render json: {
        error: "Failed to create DNS leak test",
        details: response[:error]
      }, status: :service_unavailable
    end
  end

  def results
    test_id = params[:test_id]

    unless test_id.present?
      return render json: { error: "test_id parameter required" }, status: :bad_request
    end

    # Get results from external service
    response = make_external_request(
      :get,
      "#{DNS_LEAK_SERVICE_URL}/api/v1/test/#{test_id}"
    )

    if response[:success]
      test_data = response[:data]

      # Transform external service response to match our API format
      transformed_data = transform_external_response(test_data)

      render json: transformed_data
    else
      error_data = response[:error]

      if error_data&.dig("code") == "TEST_NOT_FOUND"
        render json: { error: "Test session not found or expired" }, status: :not_found
      else
        render json: {
          error: "Failed to get test results",
          details: error_data
        }, status: :service_unavailable
      end
    end
  end

  private

  def make_external_request(method, url, payload = nil)
    require "net/http"
    require "json"

    begin
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 10
      http.open_timeout = 5

      case method
      when :post
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = payload.to_json if payload
      when :get
        request = Net::HTTP::Get.new(uri)
      end

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        data = JSON.parse(response.body)
        { success: true, data: data }
      else
        error_data = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          { message: response.body, code: response.code }
        end

        { success: false, error: error_data }
      end

    rescue Net::TimeoutError, Net::OpenTimeout
      { success: false, error: { message: "DNS leak service timeout", code: "TIMEOUT" } }
    rescue Errno::ECONNREFUSED
      { success: false, error: { message: "DNS leak service unavailable", code: "SERVICE_UNAVAILABLE" } }
    rescue StandardError => e
      { success: false, error: { message: e.message, code: "UNKNOWN_ERROR" } }
    end
  end

  def transform_external_response(test_data)
    # Transform the external API response to match our frontend expectations
    leak_analysis = test_data["leak_analysis"] || {}
    test_metadata = test_data["test_metadata"] || {}

    # Convert detected resolvers to our format
    detected_resolvers = leak_analysis["detected_resolvers"] || []
    dns_servers = detected_resolvers.uniq { |r| r["ip"] }.map do |resolver|
      {
        ip: resolver["ip"],
        provider: resolver["organization"] || "Unknown",
        is_isp_server: resolver["is_isp_resolver"] == true,
        location: resolver["country"] || "Unknown"
      }
    end

    # Determine if leak is detected
    leak_detected = leak_analysis["has_leak"] == true

    # Generate analysis message based on leak severity
    analysis = case leak_analysis["leak_severity"]
    when "critical"
      "Critical DNS leak detected! Your ISP's DNS servers are being used, which can expose your browsing activity."
    when "high"
      "High-risk DNS leak detected! Multiple DNS servers from different networks are being used."
    when "medium"
      "Medium-risk DNS leak detected! Some DNS queries may not be properly protected."
    when "low"
      "Low-risk DNS configuration detected. Minor privacy concerns identified."
    else
      if leak_detected
        "DNS leak detected! Your DNS queries may not be properly protected."
      else
        "No DNS leaks detected. Your DNS queries appear to be properly routed through secure DNS servers."
      end
    end

    # Use recommendations from the external service or generate defaults
    recommendations = leak_analysis["recommendations"] || []
    if recommendations.empty?
      recommendations = if leak_detected
        [
          "Enable your VPN's DNS leak protection feature",
          "Manually configure DNS servers to use your VPN provider's DNS",
          "Consider using alternative DNS services like Cloudflare (1.1.1.1) or Quad9 (9.9.9.9)",
          "Test on different networks to ensure consistent protection"
        ]
      else
        [
          "Your DNS configuration appears secure",
          "Continue monitoring regularly, especially when switching networks",
          "Consider running extended tests to verify IPv6 protection"
        ]
      end
    end

    {
      test_id: test_data["test_id"],
      status: leak_detected ? "leak_detected" : "secure",
      client_ip: test_metadata["client_ip"] || "127.0.0.1",
      dns_servers: dns_servers,
      leak_detected: leak_detected,
      analysis: analysis,
      recommendations: recommendations,
      test_status: test_data["status"],
      created_at: test_data["created_at"],
      completed_at: test_data["completed_at"],
      duration_ms: test_data["duration_ms"]
    }
  end
end
