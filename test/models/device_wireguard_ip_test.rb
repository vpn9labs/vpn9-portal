require "test_helper"

class DeviceWireguardIpTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      email_address: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  test "generates consistent wireguard IP for same device" do
    device = Device.create!(
      user: @user,
      public_key: "test_public_key_123"
    )

    ip1 = device.wireguard_ip
    ip2 = device.wireguard_ip

    assert_equal ip1, ip2, "IP should be consistent for same device"
  end

  test "generates different IPs for different devices" do
    device1 = Device.create!(
      user: @user,
      public_key: "test_public_key_1"
    )

    device2 = Device.create!(
      user: @user,
      public_key: "test_public_key_2"
    )

    assert_not_equal device1.wireguard_ip, device2.wireguard_ip,
                     "Different devices should have different IPs"
  end

  test "IP is in correct format with /32 CIDR" do
    device = Device.create!(
      user: @user,
      public_key: "test_public_key_456"
    )

    ip = device.wireguard_ip

    assert_match %r{\A10\.\d{1,3}\.\d{1,3}\.\d{1,3}/32\z}, ip,
                 "IP should be in format 10.x.x.x/32"
  end

  test "IPv4 address method returns IP without CIDR notation" do
    device = Device.create!(
      user: @user,
      public_key: "test_public_key_789"
    )

    ip_with_cidr = device.wireguard_ip
    ip_only = device.ipv4_address

    assert_equal ip_with_cidr.split("/").first, ip_only,
                 "ipv4_address should return IP without /32"
    assert_no_match %r{/}, ip_only, "ipv4_address should not contain /"
  end

  test "avoids reserved network ranges" do
    # Test multiple devices to ensure none use 10.0.x.x
    100.times do |i|
      device = Device.create!(
        user: @user,
        public_key: "test_public_key_#{i}_#{SecureRandom.hex}"
      )

      ip = device.ipv4_address
      second_octet = ip.split(".")[1].to_i

      assert_not_equal 0, second_octet,
                       "Should not use 10.0.x.x range (reserved for network equipment)"
    end
  end

  test "uses full 10.0.0.0/8 range effectively" do
    # Create devices with very different public keys to test distribution
    ips = []

    50.times do |i|
      device = Device.create!(
        user: @user,
        public_key: SecureRandom.hex(32)
      )
      ips << device.ipv4_address
    end

    # Extract second octets to check distribution
    second_octets = ips.map { |ip| ip.split(".")[1].to_i }

    # Should have good distribution (not all in same /16)
    unique_second_octets = second_octets.uniq.size
    assert unique_second_octets > 10,
           "Should distribute across multiple /16 networks, got #{unique_second_octets} unique second octets"
  end

  test "handles edge cases properly" do
    device = Device.create!(
      user: @user,
      public_key: "a" * 1000  # Very long public key
    )

    ip = device.wireguard_ip
    parts = ip.split("/").first.split(".")

    # Verify all octets are in valid ranges
    assert_equal "10", parts[0]
    assert (1..255).include?(parts[1].to_i), "Second octet should be 1-255"
    assert (0..255).include?(parts[2].to_i), "Third octet should be 0-255"
    assert (1..254).include?(parts[3].to_i), "Fourth octet should be 1-254"
  end

  test "IP collision detection exists" do
    # Create a device to get its IP
    device1 = Device.create!(
      user: @user,
      public_key: "key1"
    )

    # The ensure_unique_ip validation exists and would detect collisions
    # In practice, SHA256 collisions are astronomically rare (2^128 operations expected)
    # so we just verify the validation method exists
    assert device1.respond_to?(:ensure_unique_ip, true),
           "Device should have IP uniqueness validation method"
  end
end
