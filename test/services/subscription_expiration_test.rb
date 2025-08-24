require "test_helper"
require "set"

class SubscriptionExpirationTest < ActiveSupport::TestCase
  class FakeSet
    def initialize
      @members = Set.new
    end
    def add(*ids)
      ids.each { |i| @members.add(i.to_s) }
    end
    def remove(*ids)
      ids.each { |i| @members.delete(i.to_s) }
    end
    def members
      @members.to_a
    end
  end

  class FakeHash
    def initialize
      @data = {}
    end
    def update(h)
      @data.merge!(h.transform_keys(&:to_s))
    end
    def clear
      @data.clear
    end
    def to_h
      @data.dup
    end
  end

  class FakeStore
    def initialize
      @sets = Hash.new { |h, k| h[k] = FakeSet.new }
      @hashes = Hash.new { |h, k| h[k] = FakeHash.new }
    end
    def set(key)
      @sets[key]
    end
    def hash(key)
      @hashes[key]
    end
  end

  def setup
    @store = FakeStore.new
    DeviceRegistry.kredis = @store
  end

  test "sync_expirations! marks subscriptions expired and deactivates devices + Redis sets" do
    user = User.create!(email_address: "exp@example.com", password: "password")
    plan = Plan.create!(name: "Basic", price: 5.0, duration_days: 30, device_limit: 3)
    d1 = user.devices.create!(public_key: "exp1")
    d2 = user.devices.create!(public_key: "exp2")

    # Active subscription that already expired by time
    sub = Subscription.create!(
      user: user,
      plan: plan,
      status: :active,
      started_at: 40.days.ago,
      expires_at: 1.hour.ago
    )

    # Pre-upsert device hashes (simulating create hook) and simulate activation then expiration sweep
    DeviceRegistry.upsert_device(d1)
    DeviceRegistry.upsert_device(d2)

    # Before sweep, devices might be considered active if we sync
    Device.sync_statuses_for_user!(user)
    assert @store.set("vpn9:user:#{user.id}:devices:active").members.any?, "Expected active set to be non-empty before sweep"

    # Now sweep expirations
    Subscription.sync_expirations!

    assert_equal "expired", sub.reload.status
    assert_empty @store.set("vpn9:user:#{user.id}:devices:active").members
    assert_empty @store.set("vpn9:devices:active").members
    assert_equal "inactive", d1.reload.status
    assert_equal "inactive", d2.reload.status
  end
end
