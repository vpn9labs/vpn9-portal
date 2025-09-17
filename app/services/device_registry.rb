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
# - Hash `vpn9:device:<device_id>` — per‑device metadata for ACTIVE devices only:
#   - id, user_id, name, public_key, ipv4, ipv6, allowed_ips
#
# Lifecycle
# - Device and Subscription callbacks call `Device.sync_statuses_for_user!` which
#   updates DB `devices.status` and diffs active ids to add/remove set members.
# - Device create/update/destroy upserts/clears the per‑device hash (active only).
# - `rebuild!` can be used for recovery to recompute everything from the DB.
#
module DeviceRegistry
  GLOBAL_ACTIVE_KEY = "vpn9:devices:active".freeze
  PREFERRED_RELAY_KEY_PREFIX = "vpn9:device-pref".freeze
  PREFERRED_RELAY_SALT = "device_registry:preferred_relay:v1".freeze
  DEFAULT_PREFERRED_RELAY_TTL = 300

  class << self
    # High-level API (active-only semantics)

    # Activate a single device: upsert metadata, then add to sets.
    # @param device [Device]
    def activate_device!(device)
      return unless device && device.user_id
      upsert_device_hash(device)
      add_to_sets(device.user_id, [ device.id ])
    rescue => e
      Rails.logger.warn "DeviceRegistry.activate_device! error: #{e.class}: #{e.message}"
    end

    # Deactivate a single device: remove from sets, then delete metadata.
    # @param user_id [String] UUID
    # @param device_id [String] UUID
    def deactivate_device!(user_id, device_id)
      remove_from_sets(user_id, [ device_id ])
      delete_device_hash(device_id)
    rescue => e
      Rails.logger.warn "DeviceRegistry.deactivate_device! error: #{e.class}: #{e.message}"
    end

    # Batch activate: upsert metadata for each device id, then add to sets.
    # @param user_id [String] UUID
    # @param device_ids [Array<String>] UUIDs
    def activate_devices!(user_id, device_ids)
      return if device_ids.blank?
      Device.where(id: device_ids).find_each { |d| upsert_device_hash(d) }
      add_to_sets(user_id, device_ids)
    rescue => e
      Rails.logger.warn "DeviceRegistry.activate_devices! error: #{e.class}: #{e.message}"
    end

    # Batch deactivate: remove from sets, then delete each device hash.
    # @param user_id [String] UUID
    # @param device_ids [Array<String>] UUIDs
    def deactivate_devices!(user_id, device_ids)
      return if device_ids.blank?
      remove_from_sets(user_id, device_ids)
      device_ids.each { |id| delete_device_hash(id) }
    rescue => e
      Rails.logger.warn "DeviceRegistry.deactivate_devices! error: #{e.class}: #{e.message}"
    end
    # Allow injection of a Kredis‑like provider (for tests)
    # @return [Module] provider responding to `.set(key)` and `.hash(key)`
    def kredis
      @kredis ||= Kredis
    end

    # Replace Kredis provider (used by tests to inject fakes)
    # @param provider [#set,#hash]
    def kredis=(provider)
      @kredis = provider
      remove_instance_variable(:@redis) if defined?(@redis)
    end

    # Allow overriding the Redis client used for preferred relay hints.
    # When not explicitly set, falls back to the provider's redis or Kredis.redis.
    # @return [Redis]
    def redis
      return @redis if defined?(@redis) && @redis

      provider = kredis
      if provider.respond_to?(:redis)
        provider.redis
      elsif defined?(Kredis) && Kredis.respond_to?(:redis)
        Kredis.redis
      else
        raise "DeviceRegistry redis provider is not configured"
      end
    end

    # Inject a Redis client for tests.
    # @param client [#setex,#get,#del]
    def redis=(client)
      @redis = client
    end

    # Kredis set of all active device IDs (as strings)
    # @return [Kredis::Types::Set]
    def global_active_set
      kredis.set(GLOBAL_ACTIVE_KEY)
    end

    # Kredis set of active device IDs (as strings) for a specific user
    # @param user_id [String] UUID
    # @return [Kredis::Types::Set]
    def user_active_set(user_id)
      kredis.set("vpn9:user:#{user_id}:devices:active")
    end

    # Per‑device hash with details needed by the control plane.
    # Fields: id, user_id, name, public_key, ipv4, ipv6, allowed_ips.
    # @param device_id [String] UUID
    # @return [Kredis::Types::Hash]
    def device_hash(device_id)
      kredis.hash("vpn9:device:#{device_id}")
    end

    # Store an encrypted preferred relay hint for a device.
    # @param device_id [String]
    # @param relay_id [String]
    # @param ttl [Integer] seconds before the hint expires (default 300)
    # @return [Boolean]
    def set_preferred_relay(device_id, relay_id, ttl: DEFAULT_PREFERRED_RELAY_TTL)
      return false if device_id.blank? || relay_id.blank?

      payload = preferred_relay_encryptor.encrypt_and_sign(relay_id.to_s)
      key = preferred_relay_key(device_id)
      expires_in = ttl.to_i

      client = redis
      if client.respond_to?(:setex)
        client.setex(key, expires_in, payload)
      elsif client.respond_to?(:set)
        client.set(key, payload, ex: expires_in)
      else
        raise NoMethodError, "Redis client does not support setex or set"
      end
      true
    rescue KeyError => e
      Rails.logger.warn "DeviceRegistry.set_preferred_relay missing configuration: #{e.message}"
      false
    rescue => e
      Rails.logger.warn "DeviceRegistry.set_preferred_relay error: #{e.class}: #{e.message}"
      false
    end

    # Consume and delete an encrypted preferred relay hint.
    # @param device_id [String]
    # @return [String, nil] relay id if available
    def consume_preferred_relay(device_id)
      return nil if device_id.blank?

      key = preferred_relay_key(device_id)
      client = redis
      raw = fetch_and_delete_hint(client, key)
      return nil if raw.blank?

      preferred_relay_encryptor.decrypt_and_verify(raw)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
      Rails.logger.warn "DeviceRegistry.consume_preferred_relay invalid payload: #{e.message}"
      nil
    rescue KeyError => e
      Rails.logger.warn "DeviceRegistry.consume_preferred_relay missing configuration: #{e.message}"
      nil
    rescue => e
      Rails.logger.warn "DeviceRegistry.consume_preferred_relay error: #{e.class}: #{e.message}"
      nil
    end

    # Peek at the preferred relay hint without deleting the key (for tests)
    # @param device_id [String]
    # @return [String, nil]
    def peek_preferred_relay(device_id)
      return nil if device_id.blank?

      key = preferred_relay_key(device_id)
      raw = redis.get(key)
      return nil if raw.blank?

      preferred_relay_encryptor.decrypt_and_verify(raw)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
      Rails.logger.warn "DeviceRegistry.peek_preferred_relay invalid payload: #{e.message}"
      nil
    rescue KeyError => e
      Rails.logger.warn "DeviceRegistry.peek_preferred_relay missing configuration: #{e.message}"
      nil
    rescue => e
      Rails.logger.warn "DeviceRegistry.peek_preferred_relay error: #{e.class}: #{e.message}"
      nil
    end

    # Upsert a device's record into Redis (metadata only).
    # Internal helper: caller enforces active-only policy.
    def upsert_device_hash(device)
      return unless device

      data = {
        "id" => device.id.to_s,
        "user_id" => device.user_id.to_s,
        "name" => device.name.to_s,
        "public_key" => device.public_key.to_s,
        "ipv4" => device.ipv4_address.to_s,
        "ipv6" => device.ipv6_address.to_s,
        "allowed_ips" => device.wireguard_addresses.to_s
      }
      h = device_hash(device.id)

      # Prefer Kredis keyword-style bulk update (aligns with README):
      #   hash.update(key1: "v1", key2: "v2")
      # When called with a variable, use double-splat of symbolized keys.
      if h.respond_to?(:update)
        begin
          h.update(**data.transform_keys { |k| k.to_sym })
          return
        rescue ArgumentError, NoMethodError
          # If update rejects kwargs or isn't compatible, try positional hash.
          begin
            h.update(data)
            return
          rescue ArgumentError, NoMethodError
            # Fall through to per-key assignment
          end
        end
      end

      if h.respond_to?(:[]=)
        data.each { |k, v| h[k] = v }
      elsif h.respond_to?(:merge!)
        h.merge!(data)
      else
        # As a last resort, attempt to call writer methods if any exist.
        data.each do |k, v|
          begin
            h.public_send("#{k}=", v)
          rescue NoMethodError
            # ignore missing writers
          end
        end
      end
    rescue => e
      Rails.logger.warn "DeviceRegistry.upsert_device_hash error: #{e.class}: #{e.message}"
    end

    # Delete a device's record from Redis (metadata only).
    def delete_device_hash(device_id)
      h = device_hash(device_id)
      if h.respond_to?(:remove)
        h.remove
      elsif h.respond_to?(:clear)
        h.clear
      end
    rescue => e
      Rails.logger.warn "DeviceRegistry.delete_device_hash error: #{e.class}: #{e.message}"
    end

    # Rebuild the entire registry from the database.
    # - Upserts hashes for active devices only; removes others
    # - Resets per‑user and global active sets to match DB state
    # @return [void]
    def rebuild!
      # Ensure DB reflects correct statuses
      User.find_each { |u| Device.sync_statuses_for_user!(u) }

      # Ensure per-device hashes exist only for active devices
      Device.find_each { |d| d.active? ? upsert_device_hash(d) : delete_device_hash(d.id) }

      # Reset per-user active sets based on DB state
      User.find_each do |u|
        current_members = user_active_set(u.id).members
        desired = u.devices.where(status: :active).pluck(:id).map(&:to_s)
        to_add = (desired - current_members)
        to_remove = (current_members - desired)
        activate_devices!(u.id, to_add) if to_add.any?
        deactivate_devices!(u.id, to_remove) if to_remove.any?
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

    # Internal helpers for sets
    def add_to_sets(user_id, device_ids)
      ids = device_ids.map(&:to_s)
      user_active_set(user_id).add(*ids)
      global_active_set.add(*ids)
    end

    def remove_from_sets(user_id, device_ids)
      ids = device_ids.map(&:to_s)
      user_active_set(user_id).remove(*ids)
      global_active_set.remove(*ids)
    end

    def preferred_relay_key(device_id)
      "#{PREFERRED_RELAY_KEY_PREFIX}:#{device_id}"
    end

    def preferred_relay_encryptor
      secret = ENV.fetch("DEVICE_PREF_SECRET")
      cache = (@preferred_relay_encryptor_cache ||= {})
      if cache[:secret] != secret
        key = ActiveSupport::KeyGenerator.new(secret).generate_key(PREFERRED_RELAY_SALT, ActiveSupport::MessageEncryptor.key_len)
        cache[:encryptor] = ActiveSupport::MessageEncryptor.new(key)
        cache[:secret] = secret
      end
      cache[:encryptor]
    end

    def fetch_and_delete_hint(client, key)
      if client.respond_to?(:getdel)
        client.getdel(key)
      else
        value = client.get(key)
        client.del(key) if value && client.respond_to?(:del)
        value
      end
    end
  end
end
