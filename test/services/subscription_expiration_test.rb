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
    # Support both kwargs and positional hash
    def update(*args, **kwargs)
      if kwargs.any?
        @data.merge!(kwargs.transform_keys(&:to_s))
      elsif args.first.is_a?(Hash)
        @data.merge!(args.first.transform_keys(&:to_s))
      end
    end
    def clear
      @data.clear
    end
    alias remove clear
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
    user = users(:one)
    plan = plans(:monthly)
    d1 = user.devices.create!(public_key: "exp1")
    d2 = user.devices.create!(public_key: "exp2")

    # Start with an active, non-expired subscription to activate devices
    sub = Subscription.create!(
      user: user,
      plan: plan,
      status: :active,
      started_at: 40.days.ago,
      expires_at: 1.hour.from_now
    )

    # Before sweep, activate devices based on current (non-expired) subscription
    Device.sync_statuses_for_user!(user)
    assert @store.set("vpn9:user:#{user.id}:devices:active").members.any?, "Expected active set to be non-empty before sweep"

    # Simulate time passing by expiring the subscription without triggering callbacks
    sub.update!(expires_at: 1.hour.ago)

    # Now sweep expirations
    Subscription.sync_expirations!

    assert_equal "expired", sub.reload.status
    assert_empty @store.set("vpn9:user:#{user.id}:devices:active").members
    assert_empty @store.set("vpn9:devices:active").members
    assert_equal "inactive", d1.reload.status
    assert_equal "inactive", d2.reload.status
  end
end
