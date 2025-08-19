class Device < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, uniqueness: true
  validates :public_key, presence: true, uniqueness: true
  validate :ensure_unique_ip, if: :public_key_changed?

  before_validation :generate_device_name, on: :create

  # Deterministic IP assignment using SHA256 hash
  # Uses 10.0.0.0/8 subnet (16.7 million possible IPs)
  # Avoids 10.0.0.0/24 for network equipment
  def wireguard_ip
    @wireguard_ip ||= calculate_wireguard_ip
  end

  # IPv6 address using ULA (Unique Local Address) fd00::/8 prefix
  # Format: fd00:9::/64 for VPN9's network
  def wireguard_ipv6
    @wireguard_ipv6 ||= calculate_wireguard_ipv6
  end

  # Returns both IPv4 and IPv6 addresses for dual-stack configuration
  def wireguard_addresses
    "#{wireguard_ip}, #{wireguard_ipv6}"
  end

  # Returns just the IPv4 without CIDR notation
  def ipv4_address
    wireguard_ip.split("/").first
  end

  # Returns just the IPv6 without CIDR notation
  def ipv6_address
    wireguard_ipv6.split("/").first
  end

  # Load word lists from files with caching
  # Format: adjective-noun-number (e.g., "swift-falcon-4823")

  class << self
    def adjectives
      @adjectives ||= load_word_list("db/english-adjectives.txt")
    end

    def nouns
      @nouns ||= load_word_list("db/english-nouns.txt")
    end

    def reload_word_lists!
      @adjectives = nil
      @nouns = nil
      adjectives
      nouns
    end

    private

    def load_word_list(file_path)
      full_path = Rails.root.join(file_path)

      unless File.exist?(full_path)
        Rails.logger.warn "Word list file not found: #{file_path}"
        return []
      end

      words = File.readlines(full_path)
                   .map(&:strip)
                   .reject(&:empty?)
                   .map { |word| word.gsub("-", "") } # Remove hyphens from compound words

      if words.empty?
        Rails.logger.warn "Word list file is empty: #{file_path}"
        return []
      end

      Rails.logger.info "Loaded #{words.length} words from #{file_path}"
      words
    rescue StandardError => e
      Rails.logger.error "Error loading word list from #{file_path}: #{e.message}"
      []
    end
  end

  private

  def calculate_wireguard_ip
    # Use SHA256 for good distribution across the IP space
    # Include created_at to ensure consistency even if ID/public_key somehow changes
    hash_input = "#{id}-#{public_key}-#{created_at&.to_i}"
    hash = Digest::SHA256.hexdigest(hash_input).to_i(16)

    # Use 10.0.0.0/8 range but avoid 10.0.0.0/24 (reserved for network equipment)
    # This gives us effectively 10.1.0.0 - 10.255.255.255
    second_octet = (hash % 255) + 1  # 1-255, avoiding 0
    third_octet = (hash >> 8) % 256  # 0-255
    fourth_octet = ((hash >> 16) % 254) + 1  # 1-254, avoiding 0 and 255

    "10.#{second_octet}.#{third_octet}.#{fourth_octet}/32"
  end

  def calculate_wireguard_ipv6
    # Use SHA256 hash with IPv6 salt for different distribution
    hash_input = "#{id}-#{public_key}-#{created_at&.to_i}-ipv6"
    hash = Digest::SHA256.hexdigest(hash_input)

    # ULA prefix fd00::/8 for private networks
    # Using fd00:9::/64 as VPN9's subnet (9 for VPN9)
    # Format: fd00:0009:0000:0000:xxxx:xxxx:xxxx:xxxx/128

    # Extract 8 groups of 16 bits from hash for the interface identifier
    # We need 64 bits (4 groups of 16 bits) for the interface ID
    group1 = hash[0..3].to_i(16)
    group2 = hash[4..7].to_i(16)
    group3 = hash[8..11].to_i(16)
    group4 = hash[12..15].to_i(16)

    # Build the IPv6 address
    # fd00:9:: is our network prefix (48 bits)
    # 0 for subnet (16 bits)
    # Then the unique interface identifier (64 bits)
    "fd00:9:0:0:#{group1.to_s(16)}:#{group2.to_s(16)}:#{group3.to_s(16)}:#{group4.to_s(16)}/128"
  end

  def ensure_unique_ip
    return unless persisted? || public_key.present?

    # Check if any other device has the same IPv4 or IPv6
    # This is a safety check - collisions should be extremely rare with SHA256
    conflicting_device = Device.where.not(id: id).find do |d|
      d.ipv4_address == ipv4_address || d.ipv6_address == ipv6_address
    end

    if conflicting_device
      # In the extremely rare case of collision, we could:
      # 1. Add a salt/nonce to the hash input
      # 2. Use a different hash algorithm
      # 3. Report the collision for manual resolution
      if conflicting_device.ipv4_address == ipv4_address
        errors.add(:base, "IPv4 address conflict detected (extremely rare). Please contact support.")
        Rails.logger.error "IPv4 collision detected: Device #{id} and #{conflicting_device.id} both got #{ipv4_address}"
      else
        errors.add(:base, "IPv6 address conflict detected (extremely rare). Please contact support.")
        Rails.logger.error "IPv6 collision detected: Device #{id} and #{conflicting_device.id} both got #{ipv6_address}"
      end
    end
  end

  def generate_device_name
    return if name.present?

    # Ensure word lists are loaded
    if self.class.adjectives.empty? || self.class.nouns.empty?
      # Fallback if word lists can't be loaded
      self.name = "device-#{SecureRandom.hex(8)}"
      return
    end

    max_attempts = 100
    attempt = 0

    while attempt < max_attempts
      # Generate a 4-digit random number for even more combinations
      # Total combinations: adjectives × nouns × 9000 numbers
      adjective = self.class.adjectives.sample
      noun = self.class.nouns.sample
      number = rand(1000..9999)
      candidate_name = "#{adjective}-#{noun}-#{number}"

      unless Device.exists?(name: candidate_name)
        self.name = candidate_name
        break
      end

      attempt += 1
    end

    if name.blank?
      # Ultimate fallback: use SecureRandom for guaranteed uniqueness
      self.name = "device-#{SecureRandom.hex(8)}"
    end
  end
end
