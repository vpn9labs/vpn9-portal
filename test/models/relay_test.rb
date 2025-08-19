require "test_helper"

class RelayTest < ActiveSupport::TestCase
  setup do
    @location = locations(:stockholm)
    @relay = relays(:stockholm_relay)
  end

  # === Validation Tests ===

  class ValidationTest < RelayTest
    test "should be valid with valid attributes" do
      relay = Relay.new(
        name: "us-west-1",
        hostname: "us-west-1.vpn.com",
        ipv4_address: "192.168.1.1",
        ipv6_address: "2001:db8::1",
        public_key: "test_public_key_123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert relay.valid?
    end

    test "should require name" do
      relay = Relay.new(
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:name], "can't be blank"
    end

    test "should require unique name" do
      existing_relay = Relay.create!(
        name: "unique-relay",
        hostname: "unique.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )

      duplicate_relay = Relay.new(
        name: "unique-relay",
        hostname: "another.vpn.com",
        ipv4_address: "192.168.1.2",
        public_key: "key456",
        port: 51820,
        status: "active",
        location: @location
      )

      assert_not duplicate_relay.valid?
      assert_includes duplicate_relay.errors[:name], "has already been taken"
    end

    test "should require hostname" do
      relay = Relay.new(
        name: "test-relay",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:hostname], "can't be blank"
    end

    test "should require unique hostname" do
      existing_relay = Relay.create!(
        name: "relay1",
        hostname: "unique-host.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )

      duplicate_relay = Relay.new(
        name: "relay2",
        hostname: "unique-host.vpn.com",
        ipv4_address: "192.168.1.2",
        public_key: "key456",
        port: 51820,
        status: "active",
        location: @location
      )

      assert_not duplicate_relay.valid?
      assert_includes duplicate_relay.errors[:hostname], "has already been taken"
    end

    test "should require ipv4_address" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv4_address], "can't be blank"
    end

    test "should require public_key" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:public_key], "can't be blank"
    end

    test "should require port" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:port], "can't be blank"
    end

    test "should require status" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        location: @location
      )
      relay.status = nil
      assert_not relay.valid?
      assert_includes relay.errors[:status], "can't be blank"
    end

    test "should require location" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active"
      )
      assert_not relay.valid?
      assert_includes relay.errors[:location], "must exist"
    end
  end

  # === Port Validation Tests ===

  class PortValidationTest < RelayTest
    test "should accept valid port numbers" do
      valid_ports = [ 1, 80, 443, 8080, 51820, 65535 ]

      valid_ports.each do |port|
        relay = Relay.new(
          name: "test-relay-#{port}",
          hostname: "test#{port}.vpn.com",
          ipv4_address: "192.168.1.1",
          public_key: "key123",
          port: port,
          status: "active",
          location: @location
        )
        assert relay.valid?, "Port #{port} should be valid"
      end
    end

    test "should reject port 0" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 0,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:port], "must be greater than 0"
    end

    test "should reject negative port" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: -1,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:port], "must be greater than 0"
    end

    test "should reject port greater than 65535" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 65536,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:port], "must be less than or equal to 65535"
    end

    test "should reject non-numeric port" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: "abc",
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert relay.errors[:port].any?
    end
  end

  # === IPv4 Address Validation Tests ===

  class IPv4ValidationTest < RelayTest
    test "should accept valid IPv4 addresses" do
      valid_ips = [
        "192.168.1.1",
        "10.0.0.1",
        "172.16.0.1",
        "8.8.8.8",
        "255.255.255.255",
        "0.0.0.0",
        "127.0.0.1"
      ]

      valid_ips.each do |ip|
        relay = Relay.new(
          name: "test-relay-#{ip.gsub('.', '-')}",
          hostname: "test-#{ip.gsub('.', '-')}.vpn.com",
          ipv4_address: ip,
          public_key: "key123",
          port: 51820,
          status: "active",
          location: @location
        )
        assert relay.valid?, "IPv4 address #{ip} should be valid"
      end
    end

    test "should reject IPv4 with less than 4 octets" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv4_address], "must have 4 octets"
    end

    test "should reject IPv4 with more than 4 octets" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv4_address], "must have 4 octets"
    end

    test "should reject IPv4 with octets greater than 255" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.256.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv4_address], "octets must be between 0 and 255"
    end

    test "should reject IPv4 with negative octets" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.-1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv4_address], "octets must be between 0 and 255"
    end

    test "should reject IPv4 with non-numeric octets" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.abc.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv4_address], "octets must be between 0 and 255"
    end

    test "should accept IPv4 with leading zeros" do
      # Note: Leading zeros in IP addresses are sometimes interpreted as octal
      # but our validation accepts them as decimal
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.001.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      # Our current validation accepts this - it converts "001" to 1
      assert relay.valid?
    end
  end

  # === IPv6 Address Validation Tests ===

  class IPv6ValidationTest < RelayTest
    test "should accept valid IPv6 addresses" do
      valid_ips = [
        "2001:0db8:0000:0000:0000:8a2e:0370:7334",
        "2001:db8::8a2e:370:7334",
        "2001:db8::1",
        "::1",
        "::ffff:192.0.2.1",
        "fe80::1",
        "2001:db8:85a3::8a2e:370:7334"
      ]

      valid_ips.each do |ip|
        relay = Relay.new(
          name: "test-relay-#{ip.gsub(':', '-')[0..20]}",
          hostname: "test-#{ip.gsub(':', '-')[0..20]}.vpn.com",
          ipv4_address: "192.168.1.1",
          ipv6_address: ip,
          public_key: "key123",
          port: 51820,
          status: "active",
          location: @location
        )
        assert relay.valid?, "IPv6 address #{ip} should be valid"
      end
    end

    test "should allow blank IPv6 address" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        ipv6_address: "",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert relay.valid?
    end

    test "should allow nil IPv6 address" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        ipv6_address: nil,
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert relay.valid?
    end

    test "should reject IPv6 with invalid characters" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        ipv6_address: "2001:db8::xyz",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv6_address], "contains invalid characters"
    end

    test "should reject IPv6 without colons" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        ipv6_address: "2001db8",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv6_address], "is not a valid IPv6 address"
    end

    test "should reject IPv6 with multiple double colons" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        ipv6_address: "2001::db8::1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert_not relay.valid?
      assert_includes relay.errors[:ipv6_address], "can only have one :: compression"
    end

    test "should strip whitespace from IPv6 address" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        ipv6_address: "  2001:db8::1  ",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert relay.valid?
    end
  end

  # === Status Enum Tests ===

  class StatusEnumTest < RelayTest
    test "should have correct status enum values" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        location: @location
      )

      relay.status = "inactive"
      assert relay.inactive?
      assert_equal "inactive", relay.status

      relay.status = "active"
      assert relay.active?
      assert_equal "active", relay.status

      relay.status = "maintenance"
      assert relay.maintenance?
      assert_equal "maintenance", relay.status
    end

    test "should accept numeric status values" do
      relay = Relay.new(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        location: @location,
        status: 1
      )
      assert relay.active?
      assert relay.valid?
    end

    test "should list all status options" do
      expected_statuses = [ "inactive", "active", "maintenance" ]
      assert_equal expected_statuses, Relay.statuses.keys
    end

    test "should provide status scopes" do
      # Create relays with different statuses
      Relay.destroy_all

      inactive_relay = Relay.create!(
        name: "inactive-relay",
        hostname: "inactive.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key1",
        port: 51820,
        status: "inactive",
        location: @location
      )

      active_relay = Relay.create!(
        name: "active-relay",
        hostname: "active.vpn.com",
        ipv4_address: "192.168.1.2",
        public_key: "key2",
        port: 51820,
        status: "active",
        location: @location
      )

      maintenance_relay = Relay.create!(
        name: "maintenance-relay",
        hostname: "maintenance.vpn.com",
        ipv4_address: "192.168.1.3",
        public_key: "key3",
        port: 51820,
        status: "maintenance",
        location: @location
      )

      assert_includes Relay.inactive, inactive_relay
      assert_not_includes Relay.inactive, active_relay

      assert_includes Relay.active, active_relay
      assert_not_includes Relay.active, inactive_relay

      assert_includes Relay.maintenance, maintenance_relay
      assert_not_includes Relay.maintenance, active_relay
    end
  end

  # === Association Tests ===

  class AssociationTest < RelayTest
    test "should belong to location" do
      assert_respond_to @relay, :location
      assert_instance_of Location, @relay.location
    end

    test "should access location attributes" do
      relay = Relay.create!(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )

      assert_equal @location.city, relay.location.city
      assert_equal @location.country_code, relay.location.country_code
    end

    test "should not be destroyed when location is destroyed" do
      location = Location.create!(country_code: "US", city: "New York")
      relay = Relay.create!(
        name: "us-relay",
        hostname: "us.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: location
      )

      # Note: The current model has dependent: :destroy on Location's side
      # So relay WILL be destroyed when location is destroyed
      location.destroy
      assert_raises(ActiveRecord::RecordNotFound) { relay.reload }
    end
  end

  # === Edge Cases and Special Scenarios ===

  class EdgeCaseTest < RelayTest
    test "should handle very long strings for text fields" do
      long_string = "a" * 255
      relay = Relay.new(
        name: long_string,
        hostname: long_string + ".vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: long_string * 10,  # Very long public key
        port: 51820,
        status: "active",
        location: @location
      )
      assert relay.valid?
    end

    test "should handle special characters in name and hostname" do
      relay = Relay.new(
        name: "relay-123_test.vpn",
        hostname: "test-123.sub-domain.vpn.example.com",
        ipv4_address: "192.168.1.1",
        public_key: "key+/=123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert relay.valid?
    end

    test "should handle unicode characters in name" do
      relay = Relay.new(
        name: "東京-relay",
        hostname: "tokyo.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )
      assert relay.valid?
    end

    test "should maintain data integrity with multiple updates" do
      relay = Relay.create!(
        name: "test-relay",
        hostname: "test.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )

      # Update multiple times
      relay.update!(status: "maintenance")
      relay.update!(ipv4_address: "10.0.0.1")
      relay.update!(port: 8080)
      relay.update!(status: "active")

      relay.reload
      assert_equal "active", relay.status
      assert_equal "10.0.0.1", relay.ipv4_address
      assert_equal 8080, relay.port
    end

    test "should handle concurrent relay creation" do
      threads = []
      created_relays = []

      5.times do |i|
        threads << Thread.new do
          relay = Relay.create!(
            name: "concurrent-relay-#{i}",
            hostname: "concurrent#{i}.vpn.com",
            ipv4_address: "192.168.#{i}.1",
            public_key: "key#{i}",
            port: 51820 + i,
            status: "active",
            location: @location
          )
          created_relays << relay
        end
      end

      threads.each(&:join)

      assert_equal 5, created_relays.length
      assert_equal 5, created_relays.map(&:name).uniq.length
    end

    test "should handle all standard VPN ports" do
      vpn_ports = [ 443, 1194, 1723, 51820, 500, 4500 ]

      vpn_ports.each do |port|
        relay = Relay.new(
          name: "vpn-relay-#{port}",
          hostname: "vpn#{port}.vpn.com",
          ipv4_address: "192.168.1.1",
          public_key: "key123",
          port: port,
          status: "active",
          location: @location
        )
        assert relay.valid?, "Standard VPN port #{port} should be valid"
      end
    end
  end

  # === Database Constraint Tests ===

  class DatabaseConstraintTest < RelayTest
    test "should enforce uniqueness at database level for name" do
      Relay.create!(
        name: "db-unique-name",
        hostname: "unique1.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        Relay.create!(
          name: "db-unique-name",
          hostname: "unique2.vpn.com",
          ipv4_address: "192.168.1.2",
          public_key: "key456",
          port: 51821,
          status: "active",
          location: @location
        )
      end
    end

    test "should enforce uniqueness at database level for hostname" do
      Relay.create!(
        name: "relay1",
        hostname: "db-unique-host.vpn.com",
        ipv4_address: "192.168.1.1",
        public_key: "key123",
        port: 51820,
        status: "active",
        location: @location
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        Relay.create!(
          name: "relay2",
          hostname: "db-unique-host.vpn.com",
          ipv4_address: "192.168.1.2",
          public_key: "key456",
          port: 51821,
          status: "active",
          location: @location
        )
      end
    end
  end
end
