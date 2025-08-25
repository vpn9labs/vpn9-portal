#
# DeviceRegistry maintains a Redis view of devices for the VPN control plane.
#
# Goals
# - Always‑on, write‑through cache of active devices (by subscription/plan limit)
# - Per‑device metadata for relay consumption without database lookups
# - Simple and testable using Kredis primitives (injectable provider)
#
# Redis keyspace (Kredis‑backed)
# - Set `vpn9:devices:active` — all active device ids (strings)
# - Set `vpn9:user:<user_id>:devices:active` — active device ids per user
# - Hash `vpn9:device:<device_id>` — per‑device metadata:
#   - id, user_id, name, public_key, ipv4, ipv6, allowed_ips
#
# Lifecycle
# - Device and Subscription callbacks call `Device.sync_statuses_for_user!` which
#   updates DB `devices.status` and diffs active ids to add/remove set members.
# - Device create/update/destroy upserts/clears the per‑device hash.
# - `rebuild!` can be used for recovery to recompute everything from the DB.
#
module DeviceRegistry
  GLOBAL_ACTIVE_KEY = "vpn9:devices:active".freeze

  class << self
    # Allow injection of a Kredis‑like provider (for tests)
    # @return [Module] provider responding to `.set(key)` and `.hash(key)`
    def kredis
      @kredis ||= Kredis
    end

    # Replace Kredis provider (used by tests to inject fakes)
    # @param provider [#set,#hash]
    def kredis=(provider)
      @kredis = provider
    end

    # Kredis set of all active device IDs (as strings)
    # @return [Kredis::Types::Set]
    def global_active_set
      kredis.set(GLOBAL_ACTIVE_KEY)
    end

    # Kredis set of active device IDs (as strings) for a specific user
    # @param user_id [Integer,String]
    # @return [Kredis::Types::Set]
    def user_active_set(user_id)
      kredis.set("vpn9:user:#{user_id}:devices:active")
    end

    # Per‑device hash with details needed by the control plane.
    # Fields: id, user_id, name, public_key, ipv4, ipv6, allowed_ips.
    # @param device_id [Integer,String]
    # @return [Kredis::Types::Hash]
    def device_hash(device_id)
      kredis.hash("vpn9:device:#{device_id}")
    end

    # Upsert a device's record into Redis.
    # @param device [Device]
    # @return [void]
    def upsert_device(device)
      data = {
        "id" => device.id.to_s,
        "user_id" => device.user_id.to_s,
        "name" => device.name.to_s,
        "public_key" => device.public_key.to_s,
        "ipv4" => device.ipv4_address.to_s,
        "ipv6" => device.ipv6_address.to_s,
        "allowed_ips" => device.wireguard_addresses.to_s
      }
      device_hash(device.id).update(data)
    rescue => e
      Rails.logger.warn "DeviceRegistry.upsert_device error: #{e.class}: #{e.message}"
    end

    # Delete a device's record from Redis.
    # @param device_id [Integer]
    # @return [void]
    def delete_device(device_id)
      device_hash(device_id).clear
    rescue => e
      Rails.logger.warn "DeviceRegistry.delete_device error: #{e.class}: #{e.message}"
    end

    # Rebuild the entire registry from the database.
    # - Upserts all device hashes
    # - Resets per‑user and global active sets to match DB state
    # @return [void]
    def rebuild!
      # Ensure DB reflects correct statuses
      User.find_each { |u| Device.sync_statuses_for_user!(u) }

      # Upsert all device records
      Device.find_each { |d| upsert_device(d) }

      # Reset per-user active sets based on DB state
      User.find_each do |u|
        current_members = user_active_set(u.id).members
        desired = u.devices.where(status: :active).pluck(:id).map(&:to_s)
        to_add = desired - current_members
        to_remove = current_members - desired
        add_active_devices(u.id, to_add.map(&:to_i)) if to_add.any?
        remove_active_devices(u.id, to_remove.map(&:to_i)) if to_remove.any?
      end

      # Reset global set from union of all active
      current_global = global_active_set.members
      desired_global = Device.where(status: :active).pluck(:id).map(&:to_s)
      add = desired_global - current_global
      rem = current_global - desired_global
      global_active_set.add(*add) if add.any?
      global_active_set.remove(*rem) if rem.any?
    rescue => e
      Rails.logger.warn "DeviceRegistry.rebuild! error: #{e.class}: #{e.message}"
    end

    # Add device ids to active sets (global and per‑user).
    # @param user_id [Integer]
    # @param device_ids [Array<Integer>]
    # @return [void]
    def add_active_devices(user_id, device_ids)
      return if device_ids.blank?

      ids = device_ids.map(&:to_s)
      user_active_set(user_id).add(*ids)
      global_active_set.add(*ids)
    rescue => e
      Rails.logger.warn "DeviceRegistry.add_active_devices error: #{e.class}: #{e.message}"
    end

    # Remove device ids from active sets (global and per‑user).
    # @param user_id [Integer]
    # @param device_ids [Array<Integer>]
    # @return [void]
    def remove_active_devices(user_id, device_ids)
      return if device_ids.blank?

      ids = device_ids.map(&:to_s)
      user_active_set(user_id).remove(*ids)
      global_active_set.remove(*ids)
    rescue => e
      Rails.logger.warn "DeviceRegistry.remove_active_devices error: #{e.class}: #{e.message}"
    end

    # Remove a single device id from all sets (on device deletion).
    # @param device_id [Integer]
    # @param user_id [Integer]
    # @return [void]
    def remove_device_everywhere(device_id, user_id)
      remove_active_devices(user_id, Array(device_id))
    end
  end
end
