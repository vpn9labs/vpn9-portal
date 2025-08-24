# Maintains a Redis registry of active devices for consumption by the control plane.
# Uses Kredis for Redis access. This feature is always enabled by default.
#
module DeviceRegistry
  GLOBAL_ACTIVE_KEY = "vpn9:devices:active".freeze

  class << self
    # Allow injection of a Kredis-like provider (for tests)
    def kredis
      @kredis ||= Kredis
    end

    def kredis=(provider)
      @kredis = provider
    end
    # Kredis set of all active device IDs (as strings)
    def global_active_set
      kredis.set(GLOBAL_ACTIVE_KEY)
    end

    # Kredis set of active device IDs (as strings) for a specific user
    def user_active_set(user_id)
      kredis.set("vpn9:user:#{user_id}:devices:active")
    end

    # Per-device hash with details needed by the control plane
    # Fields: id, user_id, name, public_key, ipv4, ipv6, allowed_ips
    def device_hash(device_id)
      kredis.hash("vpn9:device:#{device_id}")
    end

    # Upsert a device's record into Redis
    # @param device [Device]
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

    # Delete a device's record from Redis
    # @param device_id [Integer]
    def delete_device(device_id)
      device_hash(device_id).clear
    rescue => e
      Rails.logger.warn "DeviceRegistry.delete_device error: #{e.class}: #{e.message}"
    end

    # Rebuild the entire registry from the database
    # - Upserts all device hashes
    # - Resets per-user and global active sets to match DB state
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

    # Add device ids to active sets (global and per-user)
    # @param user_id [Integer]
    # @param device_ids [Array<Integer>]
    def add_active_devices(user_id, device_ids)
      return if device_ids.blank?

      ids = device_ids.map(&:to_s)
      user_active_set(user_id).add(*ids)
      global_active_set.add(*ids)
    rescue => e
      Rails.logger.warn "DeviceRegistry.add_active_devices error: #{e.class}: #{e.message}"
    end

    # Remove device ids from active sets (global and per-user)
    # @param user_id [Integer]
    # @param device_ids [Array<Integer>]
    def remove_active_devices(user_id, device_ids)
      return if device_ids.blank?

      ids = device_ids.map(&:to_s)
      user_active_set(user_id).remove(*ids)
      global_active_set.remove(*ids)
    rescue => e
      Rails.logger.warn "DeviceRegistry.remove_active_devices error: #{e.class}: #{e.message}"
    end

    # Remove a single device id from all sets. Useful on device deletion.
    # @param device_id [Integer]
    # @param user_id [Integer]
    def remove_device_everywhere(device_id, user_id)
      remove_active_devices(user_id, Array(device_id))
    end
  end
end
