# Example module showing how to use the new wireguard_ip method
# This would typically be included in Device or used by a service
module WireguardConfigurable
  extend ActiveSupport::Concern

  # Generate a WireGuard client configuration
  def generate_client_config(server_public_key:, server_endpoint:, dns: "1.1.1.1, 1.0.0.1")
    <<~CONFIG
      [Interface]
      PrivateKey = <YOUR_PRIVATE_KEY>
      Address = #{wireguard_ip}
      DNS = #{dns}

      [Peer]
      PublicKey = #{server_public_key}
      Endpoint = #{server_endpoint}
      AllowedIPs = 0.0.0.0/0, ::/0
      PersistentKeepalive = 25
    CONFIG
  end

  # Generate server-side peer configuration for this device
  def generate_server_peer_config
    <<~CONFIG
      [Peer]
      # #{name}
      PublicKey = #{public_key}
      AllowedIPs = #{wireguard_ip}
    CONFIG
  end

  # Example usage in a complete server config
  def self.generate_server_config(devices, server_private_key:, listen_port: 51820)
    peer_configs = devices.map(&:generate_server_peer_config).join("\n")

    <<~CONFIG
      [Interface]
      PrivateKey = #{server_private_key}
      Address = 10.0.0.1/8
      ListenPort = #{listen_port}

      #{peer_configs}
    CONFIG
  end
end
