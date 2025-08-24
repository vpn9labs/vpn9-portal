require "test_helper"
require "set"

class DeviceRegistryTest < ActiveSupport::TestCase
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

  test "upsert_device writes per-device fields" do
    user = User.create!(email_address: "dreg1@example.com", password: "password")
    device = user.devices.create!(public_key: "pub1")
    DeviceRegistry.upsert_device(device)
    data = @store.hash("vpn9:device:#{device.id}").to_h

    assert_equal device.id.to_s, data["id"]
    assert_equal user.id.to_s, data["user_id"]
    assert_equal device.name, data["name"]
    assert_equal device.public_key, data["public_key"]
    assert_equal device.ipv4_address, data["ipv4"]
    assert_equal device.ipv6_address, data["ipv6"]
    assert_equal device.wireguard_addresses, data["allowed_ips"]
  end

  test "device create populates hash but not active set without subscription" do
    user = User.create!(email_address: "dreg2@example.com", password: "password")
    device = user.devices.create!(public_key: "pub2")
    # Simulate after_commit callback
    DeviceRegistry.upsert_device(device)
    data = @store.hash("vpn9:device:#{device.id}").to_h
    assert_equal device.public_key, data["public_key"]
    assert_empty @store.set("global").members
    assert_empty @store.set("user:#{user.id}").members
  end

  test "subscription activates devices up to plan limit and updates sets" do
    user = User.create!(email_address: "dreg3@example.com", password: "password")
    plan = Plan.create!(name: "Basic", price: 5.0, duration_days: 30, device_limit: 2)
    d1 = user.devices.create!(public_key: "pub_a")
    d2 = user.devices.create!(public_key: "pub_b")
    d3 = user.devices.create!(public_key: "pub_c")

    Subscription.create!(user: user, plan: plan, status: :active, started_at: Time.current, expires_at: 30.days.from_now)
    # Simulate Subscription after_commit
    Device.sync_statuses_for_user!(user)

    user_set = @store.set("vpn9:user:#{user.id}:devices:active").members
    global_set = @store.set("vpn9:devices:active").members
    assert_equal 2, user_set.size
    assert_equal user_set.sort, global_set.select { |id| [d1.id, d2.id, d3.id].map(&:to_s).include?(id) }.sort
  end

  test "cancelling subscription removes devices from sets" do
    user = User.create!(email_address: "dreg4@example.com", password: "password")
    plan = Plan.create!(name: "Basic", price: 5.0, duration_days: 30, device_limit: 2)
    d1 = user.devices.create!(public_key: "pub_a1")
    d2 = user.devices.create!(public_key: "pub_b1")
    sub = Subscription.create!(user: user, plan: plan, status: :active, started_at: Time.current, expires_at: 30.days.from_now)

    assert @store.set("vpn9:user:#{user.id}:devices:active").members.any?
    sub.cancel!
    Device.sync_statuses_for_user!(user)
    assert_empty @store.set("vpn9:user:#{user.id}:devices:active").members
  end

  test "updating public_key updates allowed_ips in device hash" do
    user = User.create!(email_address: "dreg5@example.com", password: "password")
    device = user.devices.create!(public_key: "pub_old")
    DeviceRegistry.upsert_device(device)
    old_allowed = @store.hash("vpn9:device:#{device.id}").to_h["allowed_ips"]

    device.update!(public_key: "pub_new")
    DeviceRegistry.upsert_device(device)
    new_allowed = @store.hash("vpn9:device:#{device.id}").to_h["allowed_ips"]
    refute_equal old_allowed, new_allowed
  end

  test "destroy device removes from sets and deletes hash" do
    user = User.create!(email_address: "dreg6@example.com", password: "password")
    plan = Plan.create!(name: "Pro", price: 9.0, duration_days: 30, device_limit: 1)
    d = user.devices.create!(public_key: "pub_z")
    Subscription.create!(user: user, plan: plan, status: :active, started_at: Time.current, expires_at: 30.days.from_now)
    Device.sync_statuses_for_user!(user)

    assert_includes @store.set("vpn9:user:#{user.id}:devices:active").members, d.id.to_s
    d.destroy
    # Simulate after_destroy_commit behavior
    DeviceRegistry.remove_device_everywhere(d.id, user.id)
    DeviceRegistry.delete_device(d.id)
    Device.sync_statuses_for_user!(user)
    refute_includes @store.set("vpn9:user:#{user.id}:devices:active").members, d.id.to_s
    assert_empty @store.hash("vpn9:device:#{d.id}").to_h
  end

  test "rebuild repopulates hashes and sets from DB state" do
    u1 = User.create!(email_address: "rebuild1@example.com", password: "password")
    u2 = User.create!(email_address: "rebuild2@example.com", password: "password")
    plan = Plan.create!(name: "Pro2", price: 9.0, duration_days: 30, device_limit: 2)
    d1 = u1.devices.create!(public_key: "pub_r1")
    d2 = u1.devices.create!(public_key: "pub_r2")
    d3 = u2.devices.create!(public_key: "pub_r3")
    Subscription.create!(user: u1, plan: plan, status: :active, started_at: Time.current, expires_at: 30.days.from_now)

    # Clear fake store by reinitializing
    @store = FakeStore.new
    DeviceRegistry.kredis = @store

    DeviceRegistry.rebuild!

    # Hashes exist for all devices
    [ d1, d2, d3 ].each do |dev|
      assert_equal dev.public_key, @store.hash("vpn9:device:#{dev.id}").to_h["public_key"]
    end

    # Active sets reflect DB status
    assert_includes @store.set("vpn9:user:#{u1.id}:devices:active").members, d1.id.to_s
    assert_includes @store.set("vpn9:user:#{u1.id}:devices:active").members, d2.id.to_s
    assert_empty @store.set("vpn9:user:#{u2.id}:devices:active").members
    global_members = @store.set("vpn9:devices:active").members
    assert global_members.include?(d1.id.to_s) || global_members.include?(d2.id.to_s)
  end
end
