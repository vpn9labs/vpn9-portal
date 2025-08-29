require "test_helper"

class Admin::LocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = admins(:one)
    @location = locations(:stockholm)

    # Sign in as admin
    sign_in_admin(@admin)

    # Stub geocoding to avoid external API calls
    stub_geocoding
  end

  class AuthenticationTest < Admin::LocationsControllerTest
    test "should redirect to login when not authenticated" do
      sign_out_admin

      get admin_locations_url
      assert_redirected_to new_admin_session_url

      get admin_location_url(@location)
      assert_redirected_to new_admin_session_url

      get new_admin_location_url
      assert_redirected_to new_admin_session_url

      get edit_admin_location_url(@location)
      assert_redirected_to new_admin_session_url

      post admin_locations_url, params: { location: { city: "test" } }
      assert_redirected_to new_admin_session_url

      patch admin_location_url(@location), params: { location: { city: "updated" } }
      assert_redirected_to new_admin_session_url

      delete admin_location_url(@location)
      assert_redirected_to new_admin_session_url
    end
  end

  class IndexActionTest < Admin::LocationsControllerTest
    test "should get index" do
      get admin_locations_url
      assert_response :success
      assert_select "h1", "Locations"
    end

    test "should display all locations" do
      get admin_locations_url
      assert_response :success

      # Check that locations are displayed
      assert_select "td", text: /#{@location.city}/
      assert_select "td", text: /#{@location.country_code.upcase}/
    end

    test "should display relay count for each location" do
      get admin_locations_url
      assert_response :success

      # Check for relay count badges
      @location.relays.create!(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "10.0.0.1",
        public_key: "testkey123",
        port: 51820,
        status: "active"
      )

      get admin_locations_url
      assert_select "span", text: @location.relays.count.to_s
    end

    test "should include links to location actions" do
      get admin_locations_url
      assert_response :success

      assert_select "a[href=?]", admin_location_path(@location)
      assert_select "a[href=?]", edit_admin_location_path(@location), text: "Edit"
      assert_select "a[href=?]", admin_location_path(@location), text: "Delete"
    end

    test "should show new location button" do
      get admin_locations_url
      assert_response :success

      assert_select "a[href=?]", new_admin_location_path, text: "New Location"
    end

    test "should display country flags" do
      get admin_locations_url
      assert_response :success

      # Check for country flag emoji (Sweden flag for Stockholm)
      assert_select "span[title=?]", @location.country_name
    end

    test "should order locations by city and country code" do
      # Create additional locations
      london = locations(:london)
      new_york = locations(:new_york)

      get admin_locations_url
      assert_response :success

      # Verify ordering in the response
      cities = css_select("td a").map(&:text).select { |t| t.match?(/\w+/) }
      assert cities.index("Gothenburg") < cities.index("Stockholm") # Same country, alphabetical
    end
  end

  class ShowActionTest < Admin::LocationsControllerTest
    test "should show location" do
      get admin_location_url(@location)
      assert_response :success
      assert_select "h1", text: /#{@location.city}/
    end

    test "should display location details" do
      get admin_location_url(@location)
      assert_response :success

      assert_select "dd", text: @location.city
      assert_select "dd", text: /#{@location.country_code.upcase}/

      # Check coordinates display
      if @location.latitude && @location.longitude
        assert_select "dd", text: /#{@location.latitude}/
      else
        assert_select "dd", text: "N/A"
      end
    end

    test "should display associated relays" do
      relay = @location.relays.create!(
        name: "show-test-relay",
        hostname: "show-test.vpn.com",
        ipv4_address: "10.0.0.2",
        public_key: "showtestkey123",
        port: 51820,
        status: "active"
      )

      get admin_location_url(@location)
      assert_response :success

      assert_select "td", text: relay.name
      assert_select "td", text: relay.hostname
      assert_select "td", text: relay.ipv4_address
    end

    test "should show message when no relays" do
      @location.relays.destroy_all

      get admin_location_url(@location)
      assert_response :success

      assert_select "p.text-gray-500", text: "No relays configured for this location."
    end

    test "should show action buttons" do
      get admin_location_url(@location)
      assert_response :success

      assert_select "a[href=?]", edit_admin_location_path(@location), text: "Edit"
      assert_select "a[href=?]", admin_locations_path, text: "Back to Locations"
    end

    test "should display country name with flag" do
      get admin_location_url(@location)
      assert_response :success

      # Check for country name and flag in the title
      assert_select "h1", text: /#{@location.city}/
      assert_select "h1", text: /#{@location.country_name}/
    end
  end

  class NewActionTest < Admin::LocationsControllerTest
    test "should get new" do
      get new_admin_location_url
      assert_response :success
      assert_select "h1", "New Location"
    end

    test "should display form fields" do
      get new_admin_location_url
      assert_response :success

      assert_select "form[action=?]", admin_locations_path do
        assert_select "input[name=?]", "location[country_code]"
        assert_select "input[name=?]", "location[city]"
        assert_select "input[name=?]", "location[latitude]"
        assert_select "input[name=?]", "location[longitude]"
      end
    end

    test "should have cancel link" do
      get new_admin_location_url
      assert_response :success

      assert_select "a[href=?]", admin_locations_path, text: "Cancel"
    end
  end

  class CreateActionTest < Admin::LocationsControllerTest
    test "should create location with valid params" do
      assert_difference("Location.count", 1) do
        post admin_locations_url, params: {
          location: {
            country_code: "FR",
            city: "Paris",
            latitude: 48.8566,
            longitude: 2.3522
          }
        }
      end

      new_location = Location.order(:created_at).last
      assert_redirected_to admin_location_path(new_location)
      follow_redirect!
      assert_select ".bg-green-50", text: /successfully created/
    end

    test "should create location and trigger geocoding" do
      # Set up specific geocoding stub for Berlin
      Geocoder::Lookup::Test.add_stub(
        "Berlin, DE", [
          {
            "latitude" => 52.52,
            "longitude" => 13.405,
            "country" => "Germany"
          }
        ]
      )

      assert_difference("Location.count", 1) do
        post admin_locations_url, params: {
          location: {
            country_code: "DE",
            city: "Berlin"
            # Latitude and longitude will be set by geocoding
          }
        }
      end

      new_location = Location.order(:created_at).last
      assert_equal "DE", new_location.country_code
      assert_equal "Berlin", new_location.city
      # Geocoding should have set coordinates
      assert_equal 52.52, new_location.latitude.to_f
      assert_equal 13.405, new_location.longitude.to_f
    end

    test "should not create location with invalid params" do
      assert_no_difference("Location.count") do
        post admin_locations_url, params: {
          location: {
            country_code: "", # Invalid: blank
            city: "" # Invalid: blank
          }
        }
      end

      assert_response :unprocessable_content
      assert_select ".bg-red-50" # Error message container
    end

    test "should not create location with invalid country code length" do
      assert_no_difference("Location.count") do
        post admin_locations_url, params: {
          location: {
            country_code: "USA", # Invalid: must be 2 characters
            city: "New York"
          }
        }
      end

      assert_response :unprocessable_content
      assert_select ".bg-red-50", text: /is the wrong length/
    end

    test "should not create location without city" do
      assert_no_difference("Location.count") do
        post admin_locations_url, params: {
          location: {
            country_code: "US",
            city: "" # Invalid: blank
          }
        }
      end

      assert_response :unprocessable_content
      assert_select ".bg-red-50", text: /can't be blank/
    end

    test "should handle geocoding failures gracefully" do
      # Set up geocoding to return empty result (simulating failure)
      Geocoder::Lookup::Test.add_stub(
        "Unknown City, XX", []
      )

      assert_difference("Location.count", 1) do
        post admin_locations_url, params: {
          location: {
            country_code: "XX",
            city: "Unknown City"
          }
        }
      end

      new_location = Location.order(:created_at).last
      assert_nil new_location.latitude
      assert_nil new_location.longitude
      assert_redirected_to admin_location_path(new_location)
    end
  end

  class EditActionTest < Admin::LocationsControllerTest
    test "should get edit" do
      get edit_admin_location_url(@location)
      assert_response :success
      assert_select "h1", "Edit Location"
    end

    test "should populate form with existing values" do
      get edit_admin_location_url(@location)
      assert_response :success

      assert_select "input[name=?][value=?]", "location[country_code]", @location.country_code
      assert_select "input[name=?][value=?]", "location[city]", @location.city
    end

    test "should show coordinates if present" do
      @location.update!(latitude: 59.3293, longitude: 18.0686)

      get edit_admin_location_url(@location)
      assert_response :success

      assert_select "input[name=?][value=?]", "location[latitude]", "59.3293"
      assert_select "input[name=?][value=?]", "location[longitude]", "18.0686"
    end
  end

  class UpdateActionTest < Admin::LocationsControllerTest
    test "should update location with valid params" do
      patch admin_location_url(@location), params: {
        location: {
          city: "Updated City",
          country_code: "NO"
        }
      }

      assert_redirected_to admin_location_path(@location)
      follow_redirect!
      assert_select ".bg-green-50", text: /successfully updated/

      @location.reload
      assert_equal "Updated City", @location.city
      assert_equal "NO", @location.country_code
    end

    test "should trigger geocoding on city or country change" do
      # Set up specific geocoding response for Oslo
      Geocoder::Lookup::Test.add_stub(
        "Oslo, NO", [
          {
            "latitude" => 59.9139,
            "longitude" => 10.7522,
            "country" => "Norway"
          }
        ]
      )

      original_lat = @location.latitude
      original_lng = @location.longitude

      patch admin_location_url(@location), params: {
        location: {
          city: "Oslo",
          country_code: "NO"
        }
      }

      assert_redirected_to admin_location_path(@location)
      @location.reload

      # Check that geocoding was triggered and coordinates changed
      assert_equal 59.9139, @location.latitude.to_f
      assert_equal 10.7522, @location.longitude.to_f
    end

    test "should not update location with invalid params" do
      original_city = @location.city

      patch admin_location_url(@location), params: {
        location: {
          city: "", # Invalid: blank
          country_code: "INVALID" # Invalid: wrong length
        }
      }

      assert_response :unprocessable_content
      assert_select ".bg-red-50" # Error message container

      @location.reload
      assert_equal original_city, @location.city
    end

    test "should update coordinates manually" do
      patch admin_location_url(@location), params: {
        location: {
          latitude: 60.1699,
          longitude: 24.9384
        }
      }

      assert_redirected_to admin_location_path(@location)
      @location.reload

      assert_equal 60.1699, @location.latitude.to_f
      assert_equal 24.9384, @location.longitude.to_f
    end

    test "should not trigger geocoding if only coordinates change" do
      # Store original coordinates
      original_city = @location.city
      original_country = @location.country_code

      patch admin_location_url(@location), params: {
        location: {
          latitude: 60.0,
          longitude: 25.0
        }
      }

      assert_redirected_to admin_location_path(@location)
      @location.reload

      # City and country should not have changed
      assert_equal original_city, @location.city
      assert_equal original_country, @location.country_code
      # But coordinates should have been updated
      assert_equal 60.0, @location.latitude.to_f
      assert_equal 25.0, @location.longitude.to_f
    end
  end

  class DestroyActionTest < Admin::LocationsControllerTest
    test "should destroy location" do
      assert_difference("Location.count", -1) do
        delete admin_location_url(@location)
      end

      assert_redirected_to admin_locations_path
      follow_redirect!
      assert_select ".bg-green-50", text: /successfully deleted/
    end

    test "should destroy location and associated relays" do
      # First destroy any existing relays from fixtures
      @location.relays.destroy_all

      relay = @location.relays.create!(
        name: "destroy-test-relay",
        hostname: "destroy-test.vpn.com",
        ipv4_address: "10.0.0.3",
        public_key: "destroytestkey123",
        port: 51820,
        status: "active"
      )

      assert_difference("Location.count", -1) do
        assert_difference("Relay.count", -1) do
          delete admin_location_url(@location)
        end
      end

      assert_redirected_to admin_locations_path
      assert_raises(ActiveRecord::RecordNotFound) { relay.reload }
    end

    test "destroyed location should not be accessible" do
      location_id = @location.id
      delete admin_location_url(@location)

      get admin_location_url(id: location_id)
      assert_response :not_found
    end
  end

  class CountryIntegrationTest < Admin::LocationsControllerTest
    test "should display correct country names" do
      # Create locations with different country codes
      us_location = Location.create!(country_code: "US", city: "New York")
      gb_location = Location.create!(country_code: "GB", city: "London")
      jp_location = Location.create!(country_code: "JP", city: "Tokyo")

      get admin_locations_url
      assert_response :success

      # Check that country names are displayed correctly
      assert_select "span[title=?]", "United States"
      assert_select "span[title=?]", "United Kingdom"
      assert_select "span[title=?]", "Japan"
    end

    test "should display country flags" do
      get admin_locations_url
      assert_response :success

      # Check for flag emojis (they're Unicode characters)
      # Sweden flag for Stockholm
      assert_match(/🇸🇪/, response.body)
    end

    test "should handle unknown country codes" do
      location = Location.create!(country_code: "XX", city: "Unknown")

      get admin_location_url(location)
      assert_response :success

      # Should display the country code if name not found
      assert_select "dd", text: /XX/
    end
  end

  class FormValidationTest < Admin::LocationsControllerTest
    test "should show validation errors on create" do
      post admin_locations_url, params: {
        location: {
          country_code: "TOOLONG",
          city: ""
        }
      }

      assert_response :unprocessable_content
      assert_select ".bg-red-50" do
        assert_select "li", text: /Country code is the wrong length/
        assert_select "li", text: /City can't be blank/
      end
    end

    test "should show validation errors on update" do
      patch admin_location_url(@location), params: {
        location: {
          country_code: "X", # Too short
          city: ""
        }
      }

      assert_response :unprocessable_content
      assert_select ".bg-red-50" do
        assert_select "li", text: /Country code is the wrong length/
        assert_select "li", text: /City can't be blank/
      end
    end

    test "should preserve form values after validation error" do
      post admin_locations_url, params: {
        location: {
          country_code: "FR",
          city: "", # Invalid
          latitude: 48.8566,
          longitude: 2.3522
        }
      }

      assert_response :unprocessable_content
      assert_select "input[name=?][value=?]", "location[country_code]", "FR"
      assert_select "input[name=?][value=?]", "location[latitude]", "48.8566"
      assert_select "input[name=?][value=?]", "location[longitude]", "2.3522"
    end
  end

  private

  def sign_in_admin(admin)
    post admin_session_url, params: {
      email: admin.email,
      password: "password123"
    }
  end

  def sign_out_admin
    delete admin_session_url
  end

  def stub_geocoding
    # Stub geocoding to avoid external API calls
    Geocoder::Lookup::Test.add_stub(
      "Stockholm, SE", [
        {
          "coordinates" => [ 59.3293, 18.0686 ],
          "latitude" => 59.3293,
          "longitude" => 18.0686,
          "country" => "Sweden"
        }
      ]
    )

    # Default stub for any address
    Geocoder::Lookup::Test.set_default_stub([
      {
        "coordinates" => [ 50.0, 10.0 ],
        "latitude" => 50.0,
        "longitude" => 10.0
      }
    ])
  end
end
