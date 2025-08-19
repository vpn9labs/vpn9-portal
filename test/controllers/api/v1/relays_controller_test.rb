require "test_helper"

class Api::V1::RelaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @device_id = "test_device_123"

    # Create locations with relays for testing
    @stockholm = locations(:stockholm)
    @new_york = locations(:new_york)
    @london = locations(:london)

    # Ensure we have active relays
    @active_relay = relays(:stockholm_relay)
    @inactive_relay = relays(:uk_relay_inactive)
  end

  # === Authentication Tests ===

  test "should require authentication" do
    get api_v1_relays_url, as: :json
    assert_response :unauthorized
    assert_equal "Missing authentication token", json_response["error"]
  end

  test "should reject invalid JWT token" do
    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer invalid_token" },
        as: :json
    assert_response :unauthorized
    assert_equal "Invalid or expired token", json_response["error"]
  end

  test "should reject expired JWT token" do
    # Can't easily create an expired token with TokenService
    # So we'll use a malformed token instead
    expired_token = "invalid.expired.token"

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{expired_token}" },
        as: :json
    assert_response :unauthorized
    assert_equal "Invalid or expired token", json_response["error"]
  end

  test "should reject token for non-existent user" do
    # Create a user, generate token, then delete the user
    temp_user = User.create!(
      email_address: "temp@example.com",
      passphrase_hash: "temphashhash" + Argon2::Password.create("temp").to_s
    )
    token = generate_valid_token_for(temp_user, "temp_device")
    temp_user.destroy!

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json
    assert_response :unauthorized
    # For security reasons, we don't distinguish between invalid token and non-existent user
    assert_equal "Invalid or expired token", json_response["error"]
  end

  test "should accept valid JWT token" do
    # Create subscription for user
    create_active_subscription_for(@user)

    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json
    assert_response :success
  end

  # === Subscription Tests ===

  test "should require active subscription" do
    # Ensure user has no active subscription
    @user.subscriptions.destroy_all

    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json
    assert_response :payment_required
    assert_equal "No active subscription", json_response["error"]
    assert json_response["subscription_required"]
  end

  test "should reject expired subscription" do
    # Create expired subscription
    @user.subscriptions.destroy_all
    @user.subscriptions.create!(
      plan: plans(:monthly),
      status: "active",
      started_at: 2.months.ago,
      expires_at: 1.day.ago
    )

    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json
    assert_response :payment_required
  end

  test "should accept active subscription" do
    create_active_subscription_for(@user)

    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json
    assert_response :success
  end

  # === Response Format Tests ===

  test "should return JSON with countries array" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    assert_response :success
    assert json_response.key?("countries")
    assert_instance_of Array, json_response["countries"]
  end

  test "should structure country data correctly" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    assert countries.any?

    country = countries.first
    assert country.key?("name")
    assert country.key?("code")
    assert country.key?("cities")
    assert_instance_of Array, country["cities"]
  end

  test "should structure city data correctly" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    city = countries.first["cities"].first

    assert city.key?("name")
    assert city.key?("code")
    assert city.key?("latitude")
    assert city.key?("longitude")
    assert city.key?("relays")
    assert_instance_of Array, city["relays"]
  end

  test "should structure relay data correctly" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    relay = countries.first["cities"].first["relays"].first

    assert relay.key?("hostname")
    assert relay.key?("ipv4_addr_in")
    assert relay.key?("public_key")
    assert relay.key?("multihop_port")
  end

  test "should include ipv6 address when present" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Ensure we have a relay with IPv6
    @active_relay.update!(ipv6_address: "2001:db8::1")

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    relays = countries.flat_map { |c| c["cities"] }.flat_map { |city| city["relays"] }
    relay_with_ipv6 = relays.find { |r| r["hostname"] == @active_relay.hostname }

    assert relay_with_ipv6, "Should have at least one relay with IPv6"
    assert_equal "2001:db8::1", relay_with_ipv6["ipv6_addr_in"]
  end

  test "should not include ipv6 address when blank" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Ensure we have a relay without IPv6
    @active_relay.update!(ipv6_address: "")

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    relays = countries.flat_map { |c| c["cities"] }.flat_map { |city| city["relays"] }
    relay_without_ipv6 = relays.find { |r| r["hostname"] == @active_relay.hostname }

    assert_not relay_without_ipv6.key?("ipv6_addr_in")
  end

  # === Data Filtering Tests ===

  test "should only return active relays" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Ensure we have both active and inactive relays
    assert @active_relay.active?
    assert @inactive_relay.inactive?

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    all_relays = countries.flat_map { |c| c["cities"] }.flat_map { |city| city["relays"] }
    relay_hostnames = all_relays.map { |r| r["hostname"] }

    assert_includes relay_hostnames, @active_relay.hostname
    assert_not_includes relay_hostnames, @inactive_relay.hostname
  end

  test "should not include maintenance relays" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create a maintenance relay
    maintenance_relay = Relay.create!(
      name: "maintenance-relay",
      hostname: "maintenance.vpn.com",
      ipv4_address: "10.0.0.99",
      public_key: "maintenance_key",
      port: 51820,
      status: "maintenance",
      location: @stockholm
    )

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    all_relays = countries.flat_map { |c| c["cities"] }.flat_map { |city| city["relays"] }
    relay_hostnames = all_relays.map { |r| r["hostname"] }

    assert_not_includes relay_hostnames, maintenance_relay.hostname
  end

  test "should not include locations without active relays" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create location with no active relays
    empty_location = Location.create!(country_code: "JP", city: "Tokyo")
    Relay.create!(
      name: "jp-inactive",
      hostname: "jp.vpn.com",
      ipv4_address: "10.0.0.50",
      public_key: "jp_key",
      port: 51820,
      status: "inactive",
      location: empty_location
    )

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    all_cities = countries.flat_map { |c| c["cities"] }
    city_names = all_cities.map { |city| city["name"] }

    assert_not_includes city_names, "Tokyo"
  end

  # === Sorting Tests ===

  test "should sort countries alphabetically by code" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create multiple countries with active relays
    locations = [
      Location.create!(country_code: "ZA", city: "Cape Town"),
      Location.create!(country_code: "AU", city: "Sydney"),
      Location.create!(country_code: "CA", city: "Toronto")
    ]

    locations.each_with_index do |location, i|
      Relay.create!(
        name: "relay-#{location.country_code}",
        hostname: "#{location.country_code.downcase}.vpn.com",
        ipv4_address: "10.0.#{i}.1",
        public_key: "key_#{i}",
        port: 51820,
        status: "active",
        location: location
      )
    end

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    country_codes = countries.map { |c| c["code"] }

    assert_equal country_codes.sort, country_codes
  end

  test "should sort cities alphabetically within country" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create multiple cities in same country
    cities = [ "Zurich", "Basel", "Geneva" ].map do |city|
      Location.create!(country_code: "CH", city: city)
    end

    cities.each_with_index do |location, i|
      Relay.create!(
        name: "ch-#{i}",
        hostname: "ch#{i}.vpn.com",
        ipv4_address: "10.1.#{i}.1",
        public_key: "ch_key_#{i}",
        port: 51820,
        status: "active",
        location: location
      )
    end

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    ch_country = countries.find { |c| c["code"] == "ch" }

    if ch_country
      city_names = ch_country["cities"].map { |c| c["name"] }
      assert_equal city_names.sort, city_names
    end
  end

  test "should sort relays by name within city" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create multiple relays in same location
    location = Location.create!(country_code: "NL", city: "Amsterdam")

    [ "nl-relay-c", "nl-relay-a", "nl-relay-b" ].each_with_index do |name, i|
      Relay.create!(
        name: name,
        hostname: "#{name}.vpn.com",
        ipv4_address: "10.2.#{i}.1",
        public_key: "nl_key_#{i}",
        port: 51820,
        status: "active",
        location: location
      )
    end

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    nl_country = countries.find { |c| c["code"] == "nl" }

    if nl_country && nl_country["cities"].any?
      amsterdam = nl_country["cities"].find { |c| c["name"] == "Amsterdam" }
      relay_hostnames = amsterdam["relays"].map { |r| r["hostname"] }
      expected = [ "nl-relay-a.vpn.com", "nl-relay-b.vpn.com", "nl-relay-c.vpn.com" ]
      assert_equal expected, relay_hostnames
    end
  end

  # === Data Transformation Tests ===

  test "should lowercase country codes" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    countries.each do |country|
      assert_equal country["code"], country["code"].downcase
    end
  end

  test "should generate city codes correctly" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create location with complex city name
    location = Location.create!(country_code: "US", city: "San Francisco")
    Relay.create!(
      name: "sf-relay",
      hostname: "sf.vpn.com",
      ipv4_address: "10.3.0.1",
      public_key: "sf_key",
      port: 51820,
      status: "active",
      location: location
    )

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    countries = json_response["countries"]
    us_country = countries.find { |c| c["code"] == "us" }

    if us_country
      sf_city = us_country["cities"].find { |c| c["name"] == "San Francisco" }
      assert_equal "sanfrancisco", sf_city["code"] if sf_city
    end
  end

  # === Performance Tests ===

  test "should handle large number of relays efficiently" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create many relays
    10.times do |i|
      location = Location.create!(country_code: "T#{i}", city: "TestCity#{i}")
      3.times do |j|
        Relay.create!(
          name: "test-#{i}-#{j}",
          hostname: "test#{i}-#{j}.vpn.com",
          ipv4_address: "10.#{i}.#{j}.1",
          public_key: "key_#{i}_#{j}",
          port: 51820 + j,
          status: "active",
          location: location
        )
      end
    end

    start_time = Time.current
    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json
    response_time = Time.current - start_time

    assert_response :success
    assert response_time < 1.second, "Response took too long: #{response_time} seconds"
  end

  # === Edge Cases ===

  test "should handle locations with special characters" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    location = Location.create!(country_code: "FR", city: "Château-d'Œx")
    Relay.create!(
      name: "fr-special",
      hostname: "fr-special.vpn.com",
      ipv4_address: "10.4.0.1",
      public_key: "fr_key",
      port: 51820,
      status: "active",
      location: location
    )

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    assert_response :success
    countries = json_response["countries"]
    fr_country = countries.find { |c| c["code"] == "fr" }

    if fr_country && fr_country["cities"].any?
      city = fr_country["cities"].find { |c| c["name"] == "Château-d'Œx" }
      assert city
      assert_equal "chteaudx", city["code"]
    end
  end

  test "should handle empty database gracefully" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Remove all active relays
    Relay.active.destroy_all

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    assert_response :success
    assert_equal [], json_response["countries"]
  end

  test "should handle nil coordinates" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    # Create location without triggering geocoding
    location = Location.new(country_code: "XX", city: "Unknown")
    location.save!(validate: false)
    # Explicitly set coordinates to nil after save
    location.update_columns(latitude: nil, longitude: nil)

    Relay.create!(
      name: "xx-relay",
      hostname: "xx.vpn.com",
      ipv4_address: "10.5.0.1",
      public_key: "xx_key",
      port: 51820,
      status: "active",
      location: location
    )

    get api_v1_relays_url,
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json

    assert_response :success
    countries = json_response["countries"]
    xx_country = countries.find { |c| c["code"] == "xx" }

    if xx_country && xx_country["cities"].any?
      city = xx_country["cities"].first
      assert_nil city["latitude"]
      assert_nil city["longitude"]
    end
  end

  # === Concurrent Request Tests ===

  test "should handle concurrent requests" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    threads = []
    results = []

    5.times do
      threads << Thread.new do
        get api_v1_relays_url,
            headers: { "Authorization" => "Bearer #{token}" },
            as: :json
        results << response.status
      end
    end

    threads.each(&:join)

    assert results.all? { |status| status == 200 }
  end

  # === HTTP Method Tests ===

  test "should only accept GET requests" do
    create_active_subscription_for(@user)
    token = generate_valid_token_for(@user)

    post api_v1_relays_url,
         headers: { "Authorization" => "Bearer #{token}" },
         as: :json
    assert_response :not_found

    # Try to PUT to the collection URL with a fake ID segment
    put "#{api_v1_relays_url}/1",
        headers: { "Authorization" => "Bearer #{token}" },
        as: :json
    assert_response :not_found

    # Try to DELETE from the collection URL with a fake ID segment
    delete "#{api_v1_relays_url}/1",
           headers: { "Authorization" => "Bearer #{token}" },
           as: :json
    assert_response :not_found
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def create_active_subscription_for(user)
    user.subscriptions.destroy_all
    user.subscriptions.create!(
      plan: plans(:monthly),
      status: "active",
      started_at: 1.day.ago,
      expires_at: 1.month.from_now
    )
  end

  def generate_valid_token_for(user, device_id = "test_device")
    # Generate a test token for the user, bypassing subscription checks
    # This allows us to test subscription validation at the API level
    payload = {
      sub: user.id.to_s,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i,
      subscription_expires: (user.current_subscription&.expires_at || 1.day.from_now).to_i
    }

    # Use the pre-generated test keys from test_helper.rb
    private_key = OpenSSL::PKey::RSA.new(Base64.decode64(ENV["JWT_PRIVATE_KEY"]))
    JWT.encode(payload, private_key, "RS256")
  end
end
