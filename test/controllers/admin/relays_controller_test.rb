require "test_helper"

class Admin::RelaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = admins(:one)
    @relay = relays(:se_relay_1)
    @location = locations(:stockholm)

    # Sign in as admin
    sign_in_admin(@admin)
  end

  class AuthenticationTest < Admin::RelaysControllerTest
    test "should redirect to login when not authenticated" do
      sign_out_admin

      get admin_relays_url
      assert_redirected_to new_admin_session_url

      get admin_relay_url(@relay)
      assert_redirected_to new_admin_session_url

      get new_admin_relay_url
      assert_redirected_to new_admin_session_url

      get edit_admin_relay_url(@relay)
      assert_redirected_to new_admin_session_url

      post admin_relays_url, params: { relay: { name: "test" } }
      assert_redirected_to new_admin_session_url

      patch admin_relay_url(@relay), params: { relay: { name: "updated" } }
      assert_redirected_to new_admin_session_url

      delete admin_relay_url(@relay)
      assert_redirected_to new_admin_session_url
    end
  end

  class IndexActionTest < Admin::RelaysControllerTest
    test "should get index" do
      get admin_relays_url
      assert_response :success
      assert_select "h1", "Relays"
    end

    test "should display all relays" do
      get admin_relays_url
      assert_response :success

      # Check that relays are displayed
      assert_select "td", text: @relay.name
      assert_select "td", text: @relay.hostname
      assert_select "td", text: @relay.ipv4_address
    end

    test "should display relay status badges" do
      get admin_relays_url
      assert_response :success

      # Check for status badges
      assert_select "span", text: "active"
      assert_select "span", text: "maintenance"
      assert_select "span", text: "inactive"
    end

    test "should include links to relay actions" do
      get admin_relays_url
      assert_response :success

      assert_select "a[href=?]", admin_relay_path(@relay), text: @relay.name
      assert_select "a[href=?]", edit_admin_relay_path(@relay), text: "Edit"
      assert_select "a[href=?]", admin_relay_path(@relay), text: "Delete"
    end

    test "should include link to location" do
      get admin_relays_url
      assert_response :success

      assert_select "a[href=?]", admin_location_path(@location)
    end

    test "should show new relay button" do
      get admin_relays_url
      assert_response :success

      assert_select "a[href=?]", new_admin_relay_path, text: "New Relay"
    end
  end

  class ShowActionTest < Admin::RelaysControllerTest
    test "should show relay" do
      get admin_relay_url(@relay)
      assert_response :success
      assert_select "h1", @relay.name
    end

    test "should display relay details" do
      get admin_relay_url(@relay)
      assert_response :success

      assert_select "dd", text: @relay.name
      assert_select "dd", text: @relay.hostname
      assert_select "dd", text: @relay.ipv4_address
      assert_select "dd", text: @relay.port.to_s
    end

    test "should display WireGuard public key" do
      get admin_relay_url(@relay)
      assert_response :success

      assert_select "dd", text: @relay.public_key
    end

    test "should show location link" do
      get admin_relay_url(@relay)
      assert_response :success

      assert_select "a[href=?]", admin_location_path(@location)
    end

    test "should show action buttons" do
      get admin_relay_url(@relay)
      assert_response :success

      assert_select "a[href=?]", edit_admin_relay_path(@relay), text: "Edit"
      assert_select "a[href=?]", admin_relays_path, text: "Back to Relays"
      assert_select "a[href=?]", admin_relay_path(@relay), text: "Delete Relay"
    end
  end

  class NewActionTest < Admin::RelaysControllerTest
    test "should get new" do
      get new_admin_relay_url
      assert_response :success
      assert_select "h1", "New Relay"
    end

    test "should display form fields" do
      get new_admin_relay_url
      assert_response :success

      assert_select "form[action=?]", admin_relays_path do
        assert_select "input[name=?]", "relay[name]"
        assert_select "select[name=?]", "relay[location_id]"
        assert_select "input[name=?]", "relay[hostname]"
        assert_select "input[name=?]", "relay[ipv4_address]"
        assert_select "input[name=?]", "relay[ipv6_address]"
        assert_select "textarea[name=?]", "relay[public_key]"
        assert_select "input[name=?]", "relay[port]"
        assert_select "select[name=?]", "relay[status]"
      end
    end

    test "should populate location dropdown" do
      get new_admin_relay_url
      assert_response :success

      assert_select "select[name=?]", "relay[location_id]" do
        assert_select "option", count: Location.count + 1 # +1 for prompt
      end
    end
  end

  class CreateActionTest < Admin::RelaysControllerTest
    test "should create relay with valid params" do
      assert_difference("Relay.count", 1) do
        post admin_relays_url, params: {
          relay: {
            name: "new-unique-relay",
            location_id: @location.id,
            hostname: "new-unique.vpn9.com",
            ipv4_address: "192.168.1.200",
            ipv6_address: "2001:db8::1",
            public_key: "NewPublicKey123456789012345678901234567890=",
            port: 51820,
            status: "active"
          }
        }
      end

      new_relay = Relay.last
      assert_redirected_to admin_relay_path(new_relay)
      follow_redirect!
      assert_select ".bg-green-50", text: /successfully created/
    end

    test "should not create relay with invalid params" do
      assert_no_difference("Relay.count") do
        post admin_relays_url, params: {
          relay: {
            name: "", # Invalid: blank name
            location_id: @location.id,
            hostname: "",
            ipv4_address: "invalid",
            port: 0
          }
        }
      end

      assert_response :unprocessable_content
      assert_select ".bg-red-50" # Error message container
    end

    test "should not create relay with duplicate name" do
      assert_no_difference("Relay.count") do
        post admin_relays_url, params: {
          relay: {
            name: @relay.name, # Duplicate name
            location_id: @location.id,
            hostname: "unique.vpn9.com",
            ipv4_address: "192.168.1.201",
            public_key: "UniquePublicKey12345678901234567890123456=",
            port: 51820,
            status: "active"
          }
        }
      end

      assert_response :unprocessable_content
      assert_select ".bg-red-50", text: /has already been taken/
    end

    test "should not create relay with invalid IP address" do
      assert_no_difference("Relay.count") do
        post admin_relays_url, params: {
          relay: {
            name: "invalid-ip-relay",
            location_id: @location.id,
            hostname: "invalid.vpn9.com",
            ipv4_address: "256.256.256.256", # Invalid IP (each octet must be 0-255)
            public_key: "ValidPublicKey123456789012345678901234567=",
            port: 51820,
            status: "active"
          }
        }
      end

      assert_response :unprocessable_content
    end

    test "should not create relay with invalid port" do
      assert_no_difference("Relay.count") do
        post admin_relays_url, params: {
          relay: {
            name: "invalid-port-relay",
            location_id: @location.id,
            hostname: "port.vpn9.com",
            ipv4_address: "192.168.1.202",
            public_key: "ValidPublicKey123456789012345678901234567=",
            port: 70000, # Invalid: > 65535
            status: "active"
          }
        }
      end

      assert_response :unprocessable_content
    end
  end

  class EditActionTest < Admin::RelaysControllerTest
    test "should get edit" do
      get edit_admin_relay_url(@relay)
      assert_response :success
      assert_select "h1", "Edit Relay"
    end

    test "should populate form with existing values" do
      get edit_admin_relay_url(@relay)
      assert_response :success

      assert_select "input[name=?][value=?]", "relay[name]", @relay.name
      assert_select "input[name=?][value=?]", "relay[hostname]", @relay.hostname
      assert_select "input[name=?][value=?]", "relay[ipv4_address]", @relay.ipv4_address
      assert_select "textarea[name=?]", "relay[public_key]", text: @relay.public_key
    end
  end

  class UpdateActionTest < Admin::RelaysControllerTest
    test "should update relay with valid params" do
      patch admin_relay_url(@relay), params: {
        relay: {
          name: "updated-relay-unique",
          hostname: "updated-unique.vpn9.com",
          status: "maintenance"
        }
      }

      assert_redirected_to admin_relay_path(@relay)
      follow_redirect!
      assert_select ".bg-green-50", text: /successfully updated/

      @relay.reload
      assert_equal "updated-relay-unique", @relay.name
      assert_equal "updated-unique.vpn9.com", @relay.hostname
      assert_equal "maintenance", @relay.status
    end

    test "should not update relay with invalid params" do
      original_name = @relay.name

      patch admin_relay_url(@relay), params: {
        relay: {
          name: "", # Invalid: blank
          ipv4_address: "invalid"
        }
      }

      assert_response :unprocessable_content
      assert_select ".bg-red-50" # Error message container

      @relay.reload
      assert_equal original_name, @relay.name
    end

    test "should not update relay with duplicate hostname" do
      other_relay = relays(:se_relay_2)

      patch admin_relay_url(@relay), params: {
        relay: {
          hostname: other_relay.hostname # Duplicate
        }
      }

      assert_response :unprocessable_content
      assert_select ".bg-red-50", text: /has already been taken/
    end

    test "should update relay status" do
      assert_equal "active", @relay.status

      patch admin_relay_url(@relay), params: {
        relay: {
          status: "maintenance"
        }
      }

      assert_redirected_to admin_relay_path(@relay)
      @relay.reload
      assert_equal "maintenance", @relay.status
    end

    test "should update relay location" do
      new_location = locations(:new_york)

      patch admin_relay_url(@relay), params: {
        relay: {
          location_id: new_location.id
        }
      }

      assert_redirected_to admin_relay_path(@relay)
      @relay.reload
      assert_equal new_location, @relay.location
    end
  end

  class DestroyActionTest < Admin::RelaysControllerTest
    test "should destroy relay" do
      assert_difference("Relay.count", -1) do
        delete admin_relay_url(@relay)
      end

      assert_redirected_to admin_relays_path
      follow_redirect!
      assert_select ".bg-green-50", text: /successfully deleted/
    end

    test "destroyed relay should not be accessible" do
      relay_id = @relay.id
      delete admin_relay_url(@relay)

      # Try to access the deleted relay - should get 404
      get admin_relay_url(id: relay_id)
      assert_response :not_found
    end
  end

  class RelayLocationAssociationTest < Admin::RelaysControllerTest
    test "should display correct location in index" do
      get admin_relays_url
      assert_response :success

      # Check that the correct location is displayed for the relay
      assert_select "td", text: /#{@relay.location.city}/
    end

    test "should handle relay without IPv6" do
      relay_without_ipv6 = relays(:us_relay_1)
      get admin_relay_url(relay_without_ipv6)
      assert_response :success

      assert_select "dd", text: "Not configured"
    end
  end

  class StatusFilteringTest < Admin::RelaysControllerTest
    test "should display relays with different statuses" do
      get admin_relays_url
      assert_response :success

      # Check for different status badges
      assert_select ".bg-green-100", minimum: 1 # Active relays
      assert_select ".bg-yellow-100", minimum: 1 # Maintenance relays
      assert_select ".bg-red-100", minimum: 1 # Inactive relays
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
end
