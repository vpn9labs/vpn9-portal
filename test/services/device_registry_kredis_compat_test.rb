require "test_helper"

class DeviceRegistryKredisCompatTest < ActiveSupport::TestCase
  class StrictHash
    def initialize
      @data = {}
    end

    # Mimic a Kredis implementation where `update` exists but expects no args,
    # so calling `update(data)` raises ArgumentError like the observed bug.
    def update
      # no-op when called with zero args
    end

    def []=(key, value)
      @data[key.to_s] = value
    end

    def clear
      @data.clear
    end

    def to_h
      @data.dup
    end
  end

  class StrictStore
    def initialize
      @hashes = Hash.new { |h, k| h[k] = StrictHash.new }
      @sets = Hash.new { |h, k| h[k] = Set.new }
    end

    def hash(key)
      @hashes[key]
    end

    def set(key)
      # Minimal set for interface completeness in case of accidental calls
      @sets[key]
    end
  end

  def setup
    @original = DeviceRegistry.kredis
    DeviceRegistry.kredis = StrictStore.new
  end

  def teardown
    DeviceRegistry.kredis = @original
    DeviceRegistry.redis = nil
  end

  test "activate_device! falls back when hash.update rejects arguments for active devices" do
    user = users(:john)
    device = user.devices.create!(public_key: "pub_fallback")
    device.update!(status: :active)

    # This will trigger fallback path while respecting the active-only policy
    DeviceRegistry.activate_device!(device)

    data = DeviceRegistry.device_hash(device.id).to_h
    assert_equal device.id.to_s, data["id"]
    assert_equal user.id.to_s, data["user_id"]
    assert_equal device.public_key, data["public_key"]
    assert_equal device.ipv4_address, data["ipv4"]
    assert_equal device.ipv6_address, data["ipv6"]
  end
end
