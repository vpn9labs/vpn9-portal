require "ostruct"

#
# WireguardConfigService generates client and server‑side WireGuard
# configuration for a given device and relay. It aims to be deterministic,
# privacy‑preserving, and simple to consume from controllers.
#
# Responsibilities
# - Build end‑user client configs (optionally embedding the provided private key)
# - Emit server peer stanzas referencing device addresses/keys
# - Produce a full server config for a relay with multiple peers
# - Provide QR generation and human‑readable setup instructions
#
# Inputs
# - `device` must respond to: `name`, `public_key`, `wireguard_addresses`,
#   `wireguard_ip`, `wireguard_ipv6`, and `user` (for display only).
# - `relay` responds to: `public_key`, `port`, `interface`, and optionally
#   `ipv4_address` and `location`. If absent, a default stub is used.
#
# Usage
#   svc = WireguardConfigService.new(device: device, relay: relay)
#   client_conf = svc.generate_client_config(include_private_key: true, private_key: pk)
#   peer_conf   = svc.generate_server_peer_config
#   server_conf = WireguardConfigService.generate_server_config(relay: relay, devices: [device])
#
class WireguardConfigService
  # @return [Device] device for which configs are generated
  # @return [Relay] relay used in configuration (or a default stub)
  attr_reader :device, :relay

  # Initialize the service with a device and optional relay.
  # When relay is nil, a default stub is used (suitable for offline generation).
  #
  # @param device [Object] see Inputs
  # @param relay [Object, nil]
  def initialize(device:, relay: nil)
    @device = device
    @relay = relay || default_relay
  end

  # Generate client configuration file content
  #
  # If include_private_key is true and private_key is provided, embeds the
  # private key into the [Interface] section; otherwise uses a placeholder.
  #
  # @param include_private_key [Boolean]
  # @param private_key [String, nil]
  # @return [String] full WireGuard client configuration text
  def generate_client_config(include_private_key: false, private_key: nil)
    private_key_line = if include_private_key && private_key
                         private_key
    else
                         "<PASTE_YOUR_PRIVATE_KEY_HERE>"
    end

    <<~CONFIG
      # VPN9 WireGuard Configuration
      # Device: #{device.name}
      # Location: #{relay_location_name}
      # Generated: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}

      [Interface]
      PrivateKey = #{private_key_line}
      Address = #{device.wireguard_addresses}
      DNS = #{dns_servers}

      [Peer]
      PublicKey = #{relay_public_key}
      Endpoint = #{relay_endpoint}
      AllowedIPs = 0.0.0.0/0, ::/0
      PersistentKeepalive = 25
    CONFIG
  end

  # Generate QR code for mobile clients
  #
  # Converts the client configuration (without comments) into a QR code.
  # Returns nil if the `rqrcode` gem is not available.
  #
  # @return [RQRCode::QRCode, nil]
  def generate_qr_code
    require "rqrcode" if defined?(RQRCode)

    config_without_comments = generate_client_config.lines
                                                   .reject { |line| line.start_with?("#") }
                                                   .join

    RQRCode::QRCode.new(config_without_comments) if defined?(RQRCode)
  rescue LoadError
    Rails.logger.warn "RQRCode gem not installed. QR code generation unavailable."
    nil
  end

  # Generate server-side peer configuration for this device
  # @return [String] peer stanza suitable for inclusion in wg0.conf
  def generate_server_peer_config
    user_label = safe_user_label
    <<~CONFIG

      # Peer: #{device.name} (User: #{user_label})
      [Peer]
      PublicKey = #{device.public_key}
      AllowedIPs = #{device.wireguard_addresses}
      # Last connected: Never
    CONFIG
  end

  # Class method to generate complete server configuration
  #
  # Builds a complete wg server config for the given relay and list of devices.
  #
  # @param relay [Object] relay providing keys, listen port, interface, location
  # @param devices [Array<Object>] list of devices to include as peers
  # @return [String]
  def self.generate_server_config(relay:, devices: [])
    new_service = new(device: devices.first, relay: relay) if devices.any?

    <<~CONFIG
      # VPN9 WireGuard Server Configuration
      # Relay: #{relay.name}
      # Location: #{relay.respond_to?(:location) ? (relay.location&.name || 'Unknown') : 'Unknown'}
      # Generated: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}

      [Interface]
      PrivateKey = #{relay.private_key || '<GENERATE_WITH: wg genkey>'}
      Address = 10.0.0.1/8, fd00:9::1/64
      ListenPort = #{relay.port || 51820}

      # Enable IP forwarding
      PostUp = sysctl -w net.ipv4.ip_forward=1
      PostUp = sysctl -w net.ipv6.conf.all.forwarding=1
      PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
      PostUp = iptables -t nat -A POSTROUTING -o #{relay.interface || 'eth0'} -j MASQUERADE
      PostUp = ip6tables -A FORWARD -i wg0 -j ACCEPT
      PostUp = ip6tables -t nat -A POSTROUTING -o #{relay.interface || 'eth0'} -j MASQUERADE

      PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
      PostDown = iptables -t nat -D POSTROUTING -o #{relay.interface || 'eth0'} -j MASQUERADE
      PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
      PostDown = ip6tables -t nat -D POSTROUTING -o #{relay.interface || 'eth0'} -j MASQUERADE

      # Peers
      #{devices.map { |d| new(device: d, relay: relay).generate_server_peer_config }.join("\n")}
    CONFIG
  end

  # Generate setup instructions for the user
  # @return [Hash] keys: :desktop, :mobile, :config
  def generate_setup_instructions
    {
      desktop: desktop_instructions,
      mobile: mobile_instructions,
      config: generate_client_config
    }
  end

  private

  def default_relay
    # In production, this would select the best relay based on user location, load, etc.
    if defined?(Relay)
      Relay.active.first || create_default_relay_stub
    else
      create_default_relay_stub
    end
  end

  # Create a minimal relay stub for offline config generation.
  # @return [OpenStruct]
  def create_default_relay_stub
    OpenStruct.new(
      name: "Default",
      ip_address: "vpn.example.com",
      port: 51820,
      public_key: "SERVER_PUBLIC_KEY_PLACEHOLDER",
      interface: "eth0"
    )
  end

  # Relay's public key, with a readable placeholder if missing.
  # @return [String]
  def relay_public_key
    relay&.public_key || "RELAY_PUBLIC_KEY_NOT_SET"
  end

  # Compose endpoint "host:port" choosing an available address/hostname.
  # @return [String]
  def relay_endpoint
    address = relay&.respond_to?(:ipv4_address) ? relay.ipv4_address : (relay&.ip_address || "vpn.example.com")
    "#{address}:#{relay&.port || 51820}"
  end

  # Human‑friendly relay location name for comments.
  # @return [String]
  def relay_location_name
    if relay&.respond_to?(:location)
      location = relay.location
      location ? "#{location.city}, #{location.country}" : "Unknown Location"
    else
      "Default Location"
    end
  end

  # List of DNS servers (IPv4 and IPv6) for the client config.
  # @return [String]
  def dns_servers
    # Cloudflare DNS with IPv6 support
    "1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001"
  end

  # Derive a safe label for the user in comments, tolerating encryption errors.
  # @return [String]
  def safe_user_label
    begin
      email = device.user&.email_address
      email.present? ? email : "Anonymous"
    rescue ActiveRecord::Encryption::Errors::Decryption
      "Anonymous"
    end
  end

  # Desktop setup instructions string.
  # @return [String]
  def desktop_instructions
    <<~INSTRUCTIONS
      Desktop Setup Instructions:

      1. Install WireGuard:
         - Windows/Mac: Download from https://www.wireguard.com/install/
         - Linux: sudo apt install wireguard (Ubuntu/Debian)
                  sudo yum install wireguard-tools (RHEL/CentOS)

      2. Generate your key pair:
         wg genkey | tee privatekey | wg pubkey > publickey

      3. Save the configuration:
         - Copy the generated config below
         - Replace <PASTE_YOUR_PRIVATE_KEY_HERE> with your private key
         - Save as vpn9-#{device.name}.conf

      4. Import and activate:
         - GUI: Import the config file in WireGuard app
         - CLI: sudo wg-quick up ./vpn9-#{device.name}.conf
    INSTRUCTIONS
  end

  # Mobile setup instructions string.
  # @return [String]
  def mobile_instructions
    <<~INSTRUCTIONS
      Mobile Setup Instructions:

      1. Install WireGuard app:
         - iOS: Download from App Store
         - Android: Download from Google Play Store

      2. Add tunnel:
         - Tap + or "Add Tunnel"
         - Choose "Create from QR code" or "Create from file or archive"

      3. Configure:
         - Scan the QR code provided, OR
         - Import the configuration file
         - Name your tunnel: VPN9-#{device.name}

      4. Connect:
         - Toggle the switch to connect
         - You should see "Active" status when connected
    INSTRUCTIONS
  end
end
