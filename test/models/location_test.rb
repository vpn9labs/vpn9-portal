require "test_helper"

class LocationTest < ActiveSupport::TestCase
  setup do
    @location = locations(:stockholm)

    # Configure geocoder for testing
    Geocoder.configure(lookup: :test)

    # Set up default geocoding stub
    Geocoder::Lookup::Test.set_default_stub([
      {
        "latitude" => 50.0,
        "longitude" => 10.0,
        "country" => "Test Country"
      }
    ])
  end

  # Validation Tests
  class ValidationTest < LocationTest
    test "should be valid with valid attributes" do
      location = Location.new(
        country_code: "US",
        city: "New York"
      )
      assert location.valid?
    end

    test "should require country_code" do
      location = Location.new(city: "Paris")
      assert_not location.valid?
      assert_includes location.errors[:country_code], "can't be blank"
    end

    test "should require city" do
      location = Location.new(country_code: "FR")
      assert_not location.valid?
      assert_includes location.errors[:city], "can't be blank"
    end

    test "country_code should be exactly 2 characters" do
      location = Location.new(city: "Berlin")

      # Too short
      location.country_code = "D"
      assert_not location.valid?
      assert_includes location.errors[:country_code], "is the wrong length (should be 2 characters)"

      # Too long
      location.country_code = "DEU"
      assert_not location.valid?
      assert_includes location.errors[:country_code], "is the wrong length (should be 2 characters)"

      # Just right
      location.country_code = "DE"
      assert location.valid?
    end

    test "should accept country_code in any case" do
      location = Location.new(city: "London")

      location.country_code = "gb"
      assert location.valid?

      location.country_code = "GB"
      assert location.valid?

      location.country_code = "Gb"
      assert location.valid?
    end

    test "should allow blank latitude and longitude" do
      location = Location.new(
        country_code: "US",
        city: "Boston",
        latitude: nil,
        longitude: nil
      )
      assert location.valid?
    end

    test "should accept valid latitude and longitude" do
      location = Location.new(
        country_code: "AU",
        city: "Sydney",
        latitude: -33.8688,
        longitude: 151.2093
      )
      assert location.valid?
    end
  end

  # Association Tests
  class AssociationTest < LocationTest
    test "should have many relays" do
      assert_respond_to @location, :relays
      assert_kind_of ActiveRecord::Associations::CollectionProxy, @location.relays
    end

    test "should destroy associated relays when destroyed" do
      location = Location.create!(country_code: "JP", city: "Osaka")
      relay1 = location.relays.create!(
        name: "jp1-wireguard",
        hostname: "jp1.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "testkey123",
        port: 51820,
        status: "active"
      )
      relay2 = location.relays.create!(
        name: "jp2-wireguard",
        hostname: "jp2.vpn.com",
        ipv4_address: "192.168.1.2",
        public_key: "testkey456",
        port: 51820,
        status: "active"
      )

      assert_difference("Relay.count", -2) do
        location.destroy
      end

      assert_raises(ActiveRecord::RecordNotFound) { relay1.reload }
      assert_raises(ActiveRecord::RecordNotFound) { relay2.reload }
    end

    test "should count associated relays" do
      location = Location.create!(country_code: "CA", city: "Toronto")

      assert_equal 0, location.relays.count

      location.relays.create!(
        name: "ca1-wireguard",
        hostname: "ca1.vpn.com",
        ipv4_address: "192.168.2.1",
        public_key: "cakey123",
        port: 51820,
        status: "active"
      )

      assert_equal 1, location.relays.count
    end
  end

  # Geocoding Tests
  class GeocodingTest < LocationTest
    test "should geocode on create with city and country_code" do
      Geocoder::Lookup::Test.add_stub(
        "Paris, FR", [
          {
            "latitude" => 48.8566,
            "longitude" => 2.3522,
            "country" => "France"
          }
        ]
      )

      location = Location.create!(
        country_code: "FR",
        city: "Paris"
      )

      assert_equal 48.8566, location.latitude.to_f
      assert_equal 2.3522, location.longitude.to_f
    end

    test "should geocode on update when city changes" do
      Geocoder::Lookup::Test.add_stub(
        "Oslo, SE", [
          {
            "latitude" => 59.9139,
            "longitude" => 10.7522,
            "country" => "Norway"
          }
        ]
      )

      @location.update!(city: "Oslo")

      assert_equal 59.9139, @location.latitude.to_f
      assert_equal 10.7522, @location.longitude.to_f
    end

    test "should geocode on update when country_code changes" do
      Geocoder::Lookup::Test.add_stub(
        "Stockholm, NO", [
          {
            "latitude" => 60.0,
            "longitude" => 11.0,
            "country" => "Norway"
          }
        ]
      )

      @location.update!(country_code: "NO")

      assert_equal 60.0, @location.latitude.to_f
      assert_equal 11.0, @location.longitude.to_f
    end

    test "should not geocode when only latitude changes" do
      original_city = @location.city
      original_country = @location.country_code

      @location.update!(latitude: 70.0)

      assert_equal 70.0, @location.latitude.to_f
      assert_equal original_city, @location.city
      assert_equal original_country, @location.country_code
    end

    test "should not geocode when only longitude changes" do
      original_city = @location.city
      original_country = @location.country_code

      @location.update!(longitude: 20.0)

      assert_equal 20.0, @location.longitude.to_f
      assert_equal original_city, @location.city
      assert_equal original_country, @location.country_code
    end

    test "should not geocode when neither city nor country_code changes" do
      @location.latitude = 60.0
      @location.longitude = 20.0

      # Should not trigger geocoding
      assert_not @location.send(:should_geocode?)
    end

    test "should handle geocoding failure gracefully" do
      Geocoder::Lookup::Test.add_stub(
        "Nowhere, XX", []  # Empty result simulates geocoding failure
      )

      location = Location.create!(
        country_code: "XX",
        city: "Nowhere"
      )

      assert_nil location.latitude
      assert_nil location.longitude
      assert location.persisted?  # Should still save even without coordinates
    end

    test "full_address should combine city and country_code" do
      location = Location.new(
        country_code: "GB",
        city: "London"
      )

      assert_equal "London, GB", location.send(:full_address)
    end

    test "should_geocode? should be true when city changes" do
      @location.city = "Gothenburg"
      assert @location.send(:should_geocode?)
    end

    test "should_geocode? should be true when country_code changes" do
      @location.country_code = "NO"
      assert @location.send(:should_geocode?)
    end

    test "should_geocode? should be false when coordinates change" do
      @location.latitude = 60.0
      @location.longitude = 20.0
      assert_not @location.send(:should_geocode?)
    end

    test "should_geocode? should be false when city is blank" do
      @location.city = ""
      @location.country_code = "US"
      assert_not @location.send(:should_geocode?)
    end

    test "should_geocode? should be false when country_code is blank" do
      @location.city = "Paris"
      @location.country_code = ""
      assert_not @location.send(:should_geocode?)
    end
  end

  # Country Integration Tests
  class CountryIntegrationTest < LocationTest
    test "should return country object" do
      location = Location.new(country_code: "US")
      assert_instance_of ISO3166::Country, location.country
    end

    test "should return nil country for invalid country_code" do
      location = Location.new(country_code: "XX")
      # XX is not a valid ISO country code, but the gem might still return an object
      # Let's check what actually happens
      country = location.country
      if country
        assert_nil country.common_name
      else
        assert_nil country
      end
    end

    test "should return correct country_name for known countries" do
      test_cases = {
        "US" => "United States",
        "GB" => "United Kingdom",
        "FR" => "France",
        "DE" => "Germany",
        "JP" => "Japan",
        "CA" => "Canada",
        "AU" => "Australia",
        "SE" => "Sweden"
      }

      test_cases.each do |code, expected_name|
        location = Location.new(country_code: code)
        assert_includes [ expected_name, location.country&.iso_short_name ], location.country_name,
                       "Country code #{code} should return #{expected_name}"
      end
    end

    test "should return country_code as fallback for unknown countries" do
      location = Location.new(country_code: "ZZ")
      # ZZ is not a valid country code
      assert_equal "ZZ", location.country_name
    end

    test "should return country_flag emoji" do
      location = Location.new(country_code: "US")
      flag = location.country_flag

      # US flag should be 🇺🇸 (two regional indicator symbols)
      assert_equal "🇺🇸", flag
      assert_equal 2, flag.chars.length  # Emoji flags are composed of 2 characters
    end

    test "should return correct flag for various countries" do
      test_cases = {
        "GB" => "🇬🇧",
        "JP" => "🇯🇵",
        "FR" => "🇫🇷",
        "DE" => "🇩🇪",
        "CA" => "🇨🇦"
      }

      test_cases.each do |code, expected_flag|
        location = Location.new(country_code: code)
        assert_equal expected_flag, location.country_flag,
                    "Country code #{code} should return flag #{expected_flag}"
      end
    end

    test "should handle lowercase country_code for flag" do
      location = Location.new(country_code: "us")
      assert_equal "🇺🇸", location.country_flag
    end

    test "should return empty string for blank country_code flag" do
      location = Location.new(country_code: "")
      assert_equal "", location.country_flag

      location.country_code = nil
      assert_equal "", location.country_flag
    end

    test "should generate city_code from city name" do
      test_cases = {
        "New York" => "newyork",
        "San Francisco" => "sanfrancisco",
        "Los Angeles" => "losangeles",
        "St. Petersburg" => "stpetersburg",
        "São Paulo" => "sopaulo",
        "Zürich" => "zrich",
        "München" => "mnchen"
      }

      test_cases.each do |city, expected_code|
        location = Location.new(city: city)
        assert_equal expected_code, location.city_code,
                    "City '#{city}' should generate code '#{expected_code}'"
      end
    end

    test "should return nil city_code for blank city" do
      location = Location.new(city: "")
      assert_nil location.city_code

      location.city = nil
      assert_nil location.city_code
    end

    test "city_code should be lowercase and alphanumeric only" do
      location = Location.new(city: "TEST-City_123!@#")
      assert_equal "testcity123", location.city_code
    end
  end

  # Attribute Tests
  class AttributeTest < LocationTest
    test "should store decimal latitude correctly" do
      @location.latitude = 51.5074
      @location.save!
      @location.reload

      assert_in_delta 51.5074, @location.latitude.to_f, 0.0001
    end

    test "should store decimal longitude correctly" do
      @location.longitude = -0.1278
      @location.save!
      @location.reload

      assert_in_delta -0.1278, @location.longitude.to_f, 0.0001
    end

    test "should store negative coordinates" do
      # Set up specific geocoding stub for Melbourne
      Geocoder::Lookup::Test.add_stub(
        "Melbourne, AU", [
          {
            "latitude" => -37.8136,
            "longitude" => 144.9631,
            "country" => "Australia"
          }
        ]
      )

      location = Location.create!(
        country_code: "AU",
        city: "Melbourne"
      )

      assert_in_delta -37.8136, location.latitude.to_f, 0.0001
      assert_in_delta 144.9631, location.longitude.to_f, 0.0001
    end

    test "should handle coordinate boundary values" do
      location = Location.new(country_code: "XX", city: "Test")

      # Maximum latitude (North Pole)
      location.latitude = 90.0
      assert location.valid?

      # Minimum latitude (South Pole)
      location.latitude = -90.0
      assert location.valid?

      # Maximum longitude
      location.longitude = 180.0
      assert location.valid?

      # Minimum longitude
      location.longitude = -180.0
      assert location.valid?
    end
  end

  # Scope and Query Tests
  class ScopeTest < LocationTest
    test "should order locations by city" do
      # Create locations with different cities
      Location.destroy_all
      loc_c = Location.create!(country_code: "US", city: "Chicago")
      loc_a = Location.create!(country_code: "US", city: "Atlanta")
      loc_b = Location.create!(country_code: "US", city: "Boston")

      locations = Location.order(:city)

      assert_equal [ loc_a, loc_b, loc_c ], locations.to_a
    end

    test "should order locations by country_code" do
      Location.destroy_all
      loc_us = Location.create!(country_code: "US", city: "New York")
      loc_ca = Location.create!(country_code: "CA", city: "Toronto")
      loc_mx = Location.create!(country_code: "MX", city: "Mexico City")

      locations = Location.order(:country_code)

      assert_equal [ loc_ca, loc_mx, loc_us ], locations.to_a
    end

    test "should include relays efficiently" do
      # This tests that we can use includes to avoid N+1 queries
      locations = Location.includes(:relays)

      # Should not raise any errors when accessing relays
      assert_nothing_raised do
        locations.each do |location|
          location.relays.to_a
        end
      end

      # Verify includes worked
      assert locations.first.association(:relays).loaded?
    end

    test "should find locations with active relays" do
      location_with_active = Location.create!(country_code: "NL", city: "Amsterdam")
      location_with_active.relays.create!(
        name: "nl1",
        hostname: "nl1.vpn.com",
        ipv4_address: "10.0.0.1",
        public_key: "nlkey",
        port: 51820,
        status: "active"
      )

      location_without_active = Location.create!(country_code: "BE", city: "Brussels")
      location_without_active.relays.create!(
        name: "be1",
        hostname: "be1.vpn.com",
        ipv4_address: "10.0.0.2",
        public_key: "bekey",
        port: 51820,
        status: "inactive"
      )

      # Find locations that have active relays
      locations_with_active_relays = Location.joins(:relays).where(relays: { status: "active" }).distinct

      assert_includes locations_with_active_relays, location_with_active
      assert_not_includes locations_with_active_relays, location_without_active
    end
  end

  # Edge Cases and Special Scenarios
  class EdgeCaseTest < LocationTest
    test "should handle city names with special characters" do
      cities = [
        "São Paulo",
        "Zürich",
        "København",
        "Montréal",
        "Łódź",
        "Ñuñoa"
      ]

      cities.each do |city|
        location = Location.new(country_code: "XX", city: city)
        assert location.valid?, "Should accept city name: #{city}"
        assert_not_nil location.city_code
      end
    end

    test "should handle country codes case-insensitively" do
      location1 = Location.new(country_code: "us", city: "Test")
      location2 = Location.new(country_code: "US", city: "Test")
      location3 = Location.new(country_code: "Us", city: "Test")

      assert location1.valid?
      assert location2.valid?
      assert location3.valid?

      # All should produce the same flag
      assert_equal location1.country_flag, location2.country_flag
      assert_equal location2.country_flag, location3.country_flag
    end

    test "should handle blank coordinates in calculations" do
      location = Location.new(country_code: "US", city: "Unknown")
      location.latitude = nil
      location.longitude = nil

      # Should not raise errors
      assert_nothing_raised do
        location.save
        location.latitude.to_f
        location.longitude.to_f
      end
    end

    test "should maintain data integrity with concurrent relay operations" do
      location = Location.create!(country_code: "ES", city: "Madrid")

      # Create multiple relays
      5.times do |i|
        location.relays.create!(
          name: "es#{i}",
          hostname: "es#{i}.vpn.com",
          ipv4_address: "10.0.#{i}.1",
          public_key: "eskey#{i}",
          port: 51820 + i,
          status: "active"
        )
      end

      assert_equal 5, location.relays.count

      # Destroy location should cascade to all relays
      location.destroy
      assert_equal 0, Relay.where(location_id: location.id).count
    end
  end
end
