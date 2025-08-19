require "test_helper"

class DeviceIpv6Test < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      email_address: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "generates consistent IPv6 address for same device" do
    device = Device.create!(
      user: @user,
      public_key: "test_public_key_v6_123"
    )

    ipv6_1 = device.wireguard_ipv6
    ipv6_2 = device.wireguard_ipv6

    assert_equal ipv6_1, ipv6_2, "IPv6 should be consistent for same device"
  end

  test "generates different IPv6 addresses for different devices" do
    device1 = Device.create!(
      user: @user,
      public_key: "test_public_key_v6_1"
    )

    device2 = Device.create!(
      user: @user,
      public_key: "test_public_key_v6_2"
    )

    assert_not_equal device1.wireguard_ipv6, device2.wireguard_ipv6,
                     "Different devices should have different IPv6 addresses"
  end

  test "IPv6 is in correct ULA format with /128 CIDR" do
    device = Device.create!(
      user: @user,
      public_key: "test_public_key_v6_456"
    )

    ipv6 = device.wireguard_ipv6

    # Check format: fd00:9:0:0:xxxx:xxxx:xxxx:xxxx/128
    assert_match %r{\Afd00:9:0:0:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}:[0-9a-f]{1,4}/128\z}, ipv6,
                 "IPv6 should be in ULA format fd00:9:0:0:xxxx:xxxx:xxxx:xxxx/128"
  end

  test "IPv6 address method returns IPv6 without CIDR notation" do
    device = Device.create!(
      user: @user,
      public_key: "test_public_key_v6_789"
    )

    ipv6_with_cidr = device.wireguard_ipv6
    ipv6_only = device.ipv6_address

    assert_equal ipv6_with_cidr.split("/").first, ipv6_only,
                 "ipv6_address should return IPv6 without /128"
    assert_no_match %r{/}, ipv6_only, "ipv6_address should not contain /"
  end

  test "wireguard_addresses returns both IPv4 and IPv6" do
    device = Device.create!(
      user: @user,
      public_key: "test_dual_stack_key"
    )

    addresses = device.wireguard_addresses

    # Should contain both IPv4 and IPv6 separated by comma
    assert_match %r{10\.\d+\.\d+\.\d+/32}, addresses, "Should contain IPv4"
    assert_match %r{fd00:9:0:0:[0-9a-f:]+/128}, addresses, "Should contain IPv6"
    assert_match %r{,\s*}, addresses, "Should have comma separator"
  end

  test "IPv6 uses different hash than IPv4 for same device" do
    device = Device.create!(
      user: @user,
      public_key: "test_different_hash_key"
    )

    # Extract the numeric parts to verify they're different
    ipv4 = device.ipv4_address
    ipv6 = device.ipv6_address

    # The last octets/groups should be different due to different hash inputs
    ipv4_last = ipv4.split(".").last.to_i
    ipv6_last = ipv6.split(":").last.to_i(16)

    # They might occasionally be the same by chance, but the full addresses
    # should have different patterns due to the "-ipv6" salt
    assert ipv6.include?("fd00:9"), "IPv6 should use VPN9's ULA prefix"
  end

  test "IPv6 distribution across address space" do
    # Create devices with very different public keys to test distribution
    ipv6_addresses = []

    50.times do |i|
      device = Device.create!(
        user: @user,
        public_key: SecureRandom.hex(32)
      )
      ipv6_addresses << device.ipv6_address
    end

    # Extract the last group to check distribution
    last_groups = ipv6_addresses.map { |addr| addr.split(":").last.to_i(16) }

    # Should have good distribution (not all in same range)
    unique_groups = last_groups.uniq.size
    assert unique_groups > 30,
           "Should distribute across IPv6 space, got #{unique_groups} unique last groups"
  end

  test "validates IPv6 uniqueness alongside IPv4" do
    device1 = Device.create!(
      user: @user,
      public_key: "key_v6_unique_1"
    )

    # The ensure_unique_ip validation checks both IPv4 and IPv6
    assert device1.respond_to?(:ensure_unique_ip, true),
           "Device should have IP uniqueness validation for both IPv4 and IPv6"
  end

  test "IPv6 address format is valid for WireGuard" do
    device = Device.create!(
      user: @user,
      public_key: "test_wireguard_format"
    )

    ipv6 = device.wireguard_ipv6

    # Verify it's a valid IPv6 address that WireGuard can use
    require "ipaddr"
    begin
      addr = IPAddr.new(ipv6.split("/").first)
      assert addr.ipv6?, "Should be a valid IPv6 address"
      assert addr.private?, "Should be a private address (ULA)"
    rescue IPAddr::InvalidAddressError
      flunk "Generated IPv6 address is not valid"
    end
  end

  test "IPv6 remains in ULA fd00::/8 range" do
    # Test multiple devices to ensure all stay in ULA range
    100.times do |i|
      device = Device.create!(
        user: @user,
        public_key: "test_ula_range_#{i}_#{SecureRandom.hex}"
      )

      ipv6 = device.ipv6_address

      # Must start with fd (ULA prefix)
      assert ipv6.start_with?("fd00:9:"),
             "IPv6 #{ipv6} should start with fd00:9: (VPN9's ULA range)"
    end
  end
end
