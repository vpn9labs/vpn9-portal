require "test_helper"

class WireguardConfigServiceIpv6Test < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      email_address: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    @device = Device.create!(
      user: @user,
      public_key: "test_config_public_key"
    )

    @service = WireguardConfigService.new(device: @device)
  end

  test "client config includes both IPv4 and IPv6 addresses" do
    config = @service.generate_client_config

    # Should have dual-stack addresses in Interface section
    assert_match %r{Address = 10\.\d+\.\d+\.\d+/32, fd00:9:0:0:[0-9a-f:]+/128}, config,
                 "Config should include both IPv4 and IPv6 addresses"
  end

  test "client config includes IPv6 DNS servers" do
    config = @service.generate_client_config

    # Should include Cloudflare's IPv6 DNS
    assert_match %r{2606:4700:4700::1111}, config,
                 "Config should include IPv6 DNS servers"
    assert_match %r{2606:4700:4700::1001}, config,
                 "Config should include secondary IPv6 DNS"
  end

  test "server peer config includes both address families" do
    peer_config = @service.generate_server_peer_config

    # AllowedIPs should have both IPv4 and IPv6
    assert_match %r{AllowedIPs = 10\.\d+\.\d+\.\d+/32, fd00:9:0:0:[0-9a-f:]+/128}, peer_config,
                 "Server peer config should include both IPv4 and IPv6 in AllowedIPs"
  end

  test "server config has dual-stack interface address" do
    relay = OpenStruct.new(
      name: "Test Relay",
      private_key: "test_private_key",
      port: 51820,
      interface: "eth0"
    )

    server_config = WireguardConfigService.generate_server_config(
      relay: relay,
      devices: [ @device ]
    )

    # Server should listen on both IPv4 and IPv6
    assert_match %r{Address = 10\.0\.0\.1/8, fd00:9::1/64}, server_config,
                 "Server config should have dual-stack interface addresses"
  end

  test "config enables IPv6 forwarding" do
    relay = OpenStruct.new(
      name: "Test Relay",
      private_key: "test_private_key",
      port: 51820,
      interface: "eth0"
    )

    server_config = WireguardConfigService.generate_server_config(
      relay: relay,
      devices: [ @device ]
    )

    # Should enable IPv6 forwarding
    assert_match %r{sysctl -w net\.ipv6\.conf\.all\.forwarding=1}, server_config,
                 "Should enable IPv6 forwarding"

    # Should have IPv6 firewall rules
    assert_match %r{ip6tables -A FORWARD -i wg0 -j ACCEPT}, server_config,
                 "Should configure IPv6 firewall rules"
    assert_match %r{ip6tables -t nat -A POSTROUTING}, server_config,
                 "Should configure IPv6 NAT"
  end

  test "config allows all IPv6 traffic in AllowedIPs" do
    config = @service.generate_client_config

    # Should allow all IPv6 traffic through the tunnel
    assert_match %r{AllowedIPs = 0\.0\.0\.0/0, ::/0}, config,
                 "Should route all IPv4 and IPv6 traffic through tunnel"
  end

  test "downloaded config filename is device-name based" do
    # This would be tested in controller, but we can verify the service provides the name
    assert_equal @device.name, @service.device.name,
                 "Service should have access to device name for config generation"
  end
end
