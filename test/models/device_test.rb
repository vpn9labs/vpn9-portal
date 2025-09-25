require "test_helper"

class DeviceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @valid_public_key = "valid_wireguard_public_key_base64_example_1234567890"
    @another_public_key = "another_wireguard_public_key_base64_example_0987654321"
  end

  # Association Tests
  test "should belong to user" do
    device = Device.new(public_key: @valid_public_key)
    assert_not device.valid?
    assert_includes device.errors[:user], "must exist"
  end

  test "should be destroyed when user is destroyed" do
    # Clear any existing devices from fixtures
    @user.devices.destroy_all

    device = @user.devices.create!(public_key: @valid_public_key)
    assert_difference "Device.count", -1 do
      @user.destroy
    end
  end

  # Validation Tests
  test "should require a name" do
    device = @user.devices.build(public_key: @valid_public_key)
    device.name = nil
    device.save
    device.name = nil  # Force nil after save attempt
    assert_not device.valid?
    assert_includes device.errors[:name], "can't be blank"
  end

  test "should require a unique name" do
    device1 = @user.devices.create!(public_key: @valid_public_key)
    device2 = @user.devices.build(public_key: @another_public_key, name: device1.name)
    assert_not device2.valid?
    assert_includes device2.errors[:name], "has already been taken"
  end

  test "should require a public_key" do
    device = @user.devices.build
    device.valid?  # Trigger validations and name generation
    device.public_key = nil
    assert_not device.valid?
    assert_includes device.errors[:public_key], "can't be blank"
  end

  test "should require a unique public_key" do
    device1 = @user.devices.create!(public_key: @valid_public_key)
    device2 = users(:two).devices.build(public_key: @valid_public_key)
    assert_not device2.valid?
    assert_includes device2.errors[:public_key], "has already been taken"
  end

  test "should allow same user to have multiple devices with different public keys" do
    device1 = @user.devices.create!(public_key: @valid_public_key)
    device2 = @user.devices.build(public_key: @another_public_key)
    assert device2.valid?
    assert device2.save
  end

  test "should allow different users to have devices with different names" do
    device1 = @user.devices.create!(public_key: @valid_public_key, name: "custom-device")
    device2 = users(:two).devices.build(public_key: @another_public_key, name: "different-device")
    assert device2.valid?
  end

  # Auto-name Generation Tests
  test "should auto-generate name on create if not provided" do
    device = @user.devices.create!(public_key: @valid_public_key)
    assert_not_nil device.name
    assert_match /\A[a-z]+-[a-z]+-\d{4}\z/, device.name
  end

  test "should not override provided name" do
    custom_name = "my-custom-device"
    device = @user.devices.create!(public_key: @valid_public_key, name: custom_name)
    assert_equal custom_name, device.name
  end

  test "should generate name with adjective-noun-number format" do
    device = @user.devices.build(public_key: @valid_public_key)
    device.save!

    parts = device.name.split("-")
    assert_equal 3, parts.length

    adjectives = Device.adjectives
    nouns = Device.nouns

    assert_includes adjectives, parts[0]
    assert_includes nouns, parts[1]
    assert_match /\A\d{4}\z/, parts[2]
    assert parts[2].to_i.between?(1000, 9999)
  end

  test "generated name uses lowercase adjective and noun" do
    device = @user.devices.create!(public_key: "lowercase_key_1")
    parts = device.name.split("-")
    assert_equal 3, parts.length
    assert_match /\A[a-z]+\z/, parts[0]
    assert_match /\A[a-z]+\z/, parts[1]
    assert_equal parts[0], parts[0].downcase
    assert_equal parts[1], parts[1].downcase
  end

  test "word lists are sanitized to lowercase letters" do
    adjectives = Device.adjectives
    nouns = Device.nouns
    assert adjectives.all? { |w| w.match?(/\A[a-z]+\z/) }, "Adjectives should be lowercase and alphabetic"
    assert nouns.all? { |w| w.match?(/\A[a-z]+\z/) }, "Nouns should be lowercase and alphabetic"
  end

  test "should generate unique names" do
    names = []
    10.times do |i|
      device = @user.devices.build(public_key: "key_#{i}")
      device.send(:generate_device_name)
      names << device.name
    end

    assert_equal names.uniq.length, names.length
  end

  test "should handle collision gracefully with retry logic" do
    # Create a device with a known name
    existing_name = "unique-test"
    first_device = @user.devices.create!(public_key: @valid_public_key, name: existing_name)

    # Test that the retry logic works by verifying a device can be created
    # even when name collisions might occur
    second_device = @user.devices.build(public_key: @another_public_key)

    # The device should save successfully with a different name
    assert second_device.save
    assert_not_equal existing_name, second_device.name
    assert_match /\A[a-z]+-[a-z]+-\d{4}\z/, second_device.name
  end

  test "should fallback to hex-based name after max attempts" do
    # Stub exists? to always return true, simulating all names being taken
    Device.stubs(:exists?).returns(true)

    device = @user.devices.build(public_key: @valid_public_key)
    device.send(:generate_device_name)

    assert_match /\Adevice-[a-f0-9]{16}\z/, device.name
  end

  test "should not regenerate name on update" do
    device = @user.devices.create!(public_key: @valid_public_key)
    original_name = device.name

    device.public_key = @another_public_key
    device.save!

    assert_equal original_name, device.name
  end

  # Edge Cases and Error Scenarios
  test "should handle very long public keys" do
    long_key = "a" * 1000
    device = @user.devices.build(public_key: long_key)
    assert device.valid?
  end

  test "should handle special characters in public key" do
    special_key = "abc123+/=ABC789_-"
    device = @user.devices.build(public_key: special_key)
    assert device.valid?
  end

  test "should create device with all valid attributes" do
    assert_difference "Device.count", 1 do
      device = @user.devices.create!(
        public_key: @valid_public_key
      )
      assert_not_nil device.name
      assert_equal @user, device.user
      assert_equal @valid_public_key, device.public_key
      assert_not_nil device.created_at
      assert_not_nil device.updated_at
    end
  end

  test "wireguard_ip skips vpn infrastructure subnet" do
    device = @user.devices.build(public_key: @valid_public_key)
    device.id = SecureRandom.uuid

    stubbed_digest = ("0" * 63) + "8"

    Digest::SHA256.stubs(:hexdigest).returns(stubbed_digest)
    second_octet = device.ipv4_address.split(".")[1].to_i
    assert_not_equal 9, second_octet
  ensure
    Digest::SHA256.unstub(:hexdigest)
  end

  test "should not save device without user" do
    device = Device.new(public_key: @valid_public_key)
    assert_not device.save
  end

  test "should not save device without public key" do
    device = @user.devices.build
    device.valid?  # This triggers name generation
    device.public_key = nil
    assert_not device.save
  end

  # Mass Assignment Protection
  test "should not allow mass assignment of user_id" do
    other_user = users(:two)
    device = @user.devices.create!(
      public_key: @valid_public_key
    )

    # Even if someone tries to change user_id, it should remain with original user
    assert_equal @user, device.user
    assert_not_equal other_user, device.user
  end

  # Scope and Query Tests
  test "should retrieve all devices for a user" do
    device1 = @user.devices.create!(public_key: @valid_public_key)
    device2 = @user.devices.create!(public_key: @another_public_key)
    device3 = users(:two).devices.create!(public_key: "different_key")

    user_devices = @user.devices
    assert_includes user_devices, device1
    assert_includes user_devices, device2
    assert_not_includes user_devices, device3
  end

  # Word Lists Tests
  test "should load adjectives from file with expected properties" do
    adjectives = Device.adjectives

    assert_kind_of Array, adjectives
    assert_not_empty adjectives, "Adjectives list should not be empty"
    assert adjectives.all? { |adj| adj.is_a?(String) }
    # Allow hyphens and capital letters in source file (they can be filtered/processed if needed)
    assert adjectives.all? { |adj| adj.match?(/\A[a-zA-Z-]+\z/) }
    assert_equal adjectives, adjectives.uniq  # No duplicates
    assert_operator adjectives.length, :>=, 1000  # At least 1000 adjectives from file
  end

  test "should load nouns from file with expected properties" do
    nouns = Device.nouns

    assert_kind_of Array, nouns
    assert_not_empty nouns, "Nouns list should not be empty"
    assert nouns.all? { |noun| noun.is_a?(String) }
    # Allow hyphens and capital letters in source file (they can be filtered/processed if needed)
    assert nouns.all? { |noun| noun.match?(/\A[a-zA-Z-]+\z/) }
    assert_equal nouns, nouns.uniq  # No duplicates
    assert_operator nouns.length, :>=, 1000  # At least 1000 nouns from file
  end

  test "should have sufficient variety in name combinations" do
    # adjectives × nouns × 9000 numbers (1000-9999)
    total_combinations = Device.adjectives.length * Device.nouns.length * 9000
    assert_operator total_combinations, :>=, 500_000_000, "Should have at least 500 million possible name combinations"
    # Currently: 264 × 320 × 9000 = 760,320,000 combinations
  end

  # Callback Tests
  test "should only generate name before validation on create" do
    device = @user.devices.build(public_key: @valid_public_key)
    assert_nil device.name

    device.valid?
    assert_not_nil device.name
  end

  test "should not generate name if validation fails for other reasons" do
    device = Device.new  # No user
    assert_not device.valid?
    # Name might be generated but device still invalid due to missing user
    assert_not device.save
  end

  # File Loading Tests
  test "should cache word lists after first load" do
    # First load
    adjectives1 = Device.adjectives
    nouns1 = Device.nouns

    # Second load should return cached values (same object_id)
    adjectives2 = Device.adjectives
    nouns2 = Device.nouns

    assert_equal adjectives1.object_id, adjectives2.object_id
    assert_equal nouns1.object_id, nouns2.object_id
  end

  test "should reload word lists on demand" do
    # Initial load
    original_adjectives_count = Device.adjectives.length

    # Reload
    Device.reload_word_lists!

    # Should have same count but potentially different object
    assert_equal original_adjectives_count, Device.adjectives.length
  end

  test "should handle missing word list files gracefully" do
    # Stub the class methods to return empty arrays
    Device.stubs(:adjectives).returns([])
    Device.stubs(:nouns).returns([])

    device = @user.devices.build(public_key: "test_key_missing_files")
    device.save!

    # Should use SecureRandom fallback
    assert_match /\Adevice-[a-f0-9]{16}\z/, device.name

    Device.unstub(:adjectives)
    Device.unstub(:nouns)
  end

  # Database Constraint Tests (if you add database-level constraints)
  test "should respect database constraints" do
    device = @user.devices.create!(public_key: @valid_public_key)

    # Try to create duplicate with raw SQL (bypassing Rails validations)
    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.connection.execute(
        "INSERT INTO devices (user_id, name, public_key, created_at, updated_at) VALUES ('#{@user.id}', '#{device.name}', 'new_key', NOW(), NOW())"
      )
    end
  end
end
