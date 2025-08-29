#
# Device represents a user's WireGuard client that can access the VPN.
#
# Responsibilities
# - Belongs to a User and holds the device's WireGuard public key
# - Deterministically derives unique IPv4 and IPv6 addresses (no DB columns)
# - Maintains an access `status` reflecting the user's subscription and plan
# - Generates human-friendly device names on create
# - Detects extremely rare IP collisions as a safety check
#
# Access Control
# Device access is modeled via the `status` enum:
# - `active`: device is allowed by the current subscription and within plan limits
# - `inactive`: device has no access (no subscription, expired/cancelled, or over limit)
#
# Status is synchronized automatically:
# - On device create and destroy
# - On subscription create/update/destroy (via Subscription callback)
#
# Deterministic Networking
# - IPv4 addresses are in 10.0.0.0/8, skipping 10.0.0.0/24
# - IPv6 addresses are ULA under fd00:9::/64
# - Both addresses are derived from SHA256 of stable inputs and are not stored
#
# @example Get addresses for client config
#   device.wireguard_addresses #=> "10.x.y.z/32, fd00:9:0:0:abcd:.../128"
#
# @!attribute [rw] name
#   User-facing, generated as adjective-noun-#### unless supplied.
#   @return [String]
# @!attribute [rw] public_key
#   WireGuard public key of the device.
#   @return [String]
# @!attribute [r] user_id
#   Owning user foreign key.
#   @return [String] UUID
# @!attribute [r] status
#   Access state for the device (`active` or `inactive`).
#   @return [String] enum value
# @!attribute [r] created_at
#   @return [ActiveSupport::TimeWithZone]
# @!attribute [r] updated_at
#   @return [ActiveSupport::TimeWithZone]
#
class Device < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, uniqueness: true
  validates :public_key, presence: true, uniqueness: true
  validate :ensure_unique_ip, if: :public_key_changed?

  before_validation :generate_device_name, on: :create
  before_save :reset_address_cache, if: :will_save_change_to_public_key?

  # Device access state
  enum :status, { inactive: 0, active: 1 }

  # Ensure device statuses match subscription and plan limits whenever
  # devices are created or removed for a user.
  after_create_commit :sync_user_device_statuses
  after_create_commit :update_device_registry_record
  after_update_commit :update_device_registry_record
  after_destroy_commit :remove_from_registry_and_sync

  # Recompute which devices are active for a given user based on
  # subscription state and the plan's device_limit.
  #
  # Idempotent: repeated calls yield the same end state.
  # Priority: the oldest devices (by created_at) remain active first.
  #
  # @param user [User]
  # @return [void]
  def self.sync_statuses_for_user!(user)
    return unless user

    devices = user.devices.order(:created_at)
    previous_active_ids = user.devices.where(status: :active).pluck(:id)

    if user.has_active_subscription?
      allowed = user.device_limit.to_i
      active_ids = devices.limit(allowed).pluck(:id)

      # Update in two batches to minimize queries
      user.devices.where(id: active_ids).update_all(status: statuses[:active])
      user.devices.where.not(id: active_ids).update_all(status: statuses[:inactive])

      # Update Redis registry via high-level API (active-only metadata)
      ids_to_activate = active_ids - previous_active_ids
      ids_to_deactivate = previous_active_ids - active_ids
      DeviceRegistry.activate_devices!(user.id, ids_to_activate)
      DeviceRegistry.deactivate_devices!(user.id, ids_to_deactivate)
    else
      # No active subscription → no device has access
      user.devices.update_all(status: statuses[:inactive])

      # Remove any previously active devices from registry (and their hashes)
      DeviceRegistry.deactivate_devices!(user.id, previous_active_ids)
    end
  end

  # Deterministic IPv4 assignment using SHA256 hash.
  # Uses 10.0.0.0/8 and avoids 10.0.0.0/24 for network equipment.
  #
  # @return [String] CIDR IPv4, e.g. "10.12.34.56/32"
  def wireguard_ip
    @wireguard_ip ||= calculate_wireguard_ip
  end

  # Deterministic IPv6 using ULA fd00::/8, under fd00:9::/64 for VPN9.
  #
  # @return [String] CIDR IPv6, e.g. "fd00:9:0:0:abcd:.../128"
  def wireguard_ipv6
    @wireguard_ipv6 ||= calculate_wireguard_ipv6
  end

  # Both IPv4 and IPv6 for dual-stack configuration.
  #
  # @return [String] "<ipv4/32>, <ipv6/128>"
  def wireguard_addresses
    "#{wireguard_ip}, #{wireguard_ipv6}"
  end

  # IPv4 without CIDR notation.
  # @return [String]
  def ipv4_address
    wireguard_ip.split("/").first
  end

  # IPv6 without CIDR notation.
  # @return [String]
  def ipv6_address
    wireguard_ipv6.split("/").first
  end

  # Wordlist accessors (delegation to Wordlist model)
  # Kept for backward compatibility with any callers/tests referencing
  # Device.adjectives / Device.nouns / Device.reload_word_lists!
  class << self
    # @deprecated Use Wordlist.adjectives
    def adjectives
      Wordlist.adjectives
    end

    # @deprecated Use Wordlist.nouns
    def nouns
      Wordlist.nouns
    end

    # @deprecated Use Wordlist.reload!
    def reload_word_lists!
      Wordlist.reload!
    end
  end

  private

  # Trigger device status sync for the owning user.
  # @return [void]
  def sync_user_device_statuses
    self.class.sync_statuses_for_user!(user)
  end

  # After destroy: ensure device id is removed from Redis registry then resync the rest
  def remove_from_registry_and_sync
    DeviceRegistry.deactivate_device!(user_id, id)
    self.class.sync_statuses_for_user!(user)
  end

  # Ensure per-device record is up to date in Redis after updates
  def update_device_registry_record
    if active?
      DeviceRegistry.activate_device!(self)
    else
      DeviceRegistry.deactivate_device!(user_id, id)
    end
  end

  def reset_address_cache
    @wireguard_ip = nil
    @wireguard_ipv6 = nil
  end

  # Compute stable IPv4 in 10.0.0.0/8 avoiding reserved ranges.
  # @api private
  # @return [String]
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

  # Compute stable IPv6 under fd00:9::/64 using salted SHA256.
  # @api private
  # @return [String]
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

  # Safety check against extremely rare IPv4/IPv6 collisions.
  # @api private
  # @return [void]
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

  # Generate a unique, human-friendly device name.
  # Format: adjective-noun-#### with retries, then hex fallback.
  # @api private
  # @return [void]
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
      adjective = self.class.adjectives.sample.to_s.downcase
      noun = self.class.nouns.sample.to_s.downcase
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
