# Redis Connection Test Commands for Rails Console
# Run these commands in Rails console via: bin/kamal console

puts "=" * 60
puts "Redis Connection Test Suite"
puts "=" * 60

# 1. Check Redis URL configuration
puts "\n1. Current Redis Configuration:"
puts "   REDIS_URL: #{ENV['REDIS_URL']}"
puts "   KREDIS_URL: #{ENV['KREDIS_URL']}"

# 2. Test basic Kredis connection
puts "\n2. Testing Kredis Connection:"
begin
  test_key = Kredis.string("vpn9:test:connection")
  test_key.value = "connected at #{Time.current}"
  puts "   ✓ Write test: #{test_key.value}"
  test_key.clear
  puts "   ✓ Clear test: Success"
rescue => e
  puts "   ✗ Kredis error: #{e.message}"
end

# 3. Test raw Redis connection via Kredis
puts "\n3. Testing Raw Redis Connection:"
begin
  redis = Kredis.redis
  redis.ping
  puts "   ✓ PING: PONG received"

  # Check Redis info
  info = redis.info
  puts "   ✓ Redis version: #{info['redis_version']}"
  puts "   ✓ Connected clients: #{info['connected_clients']}"
  puts "   ✓ Used memory: #{info['used_memory_human']}"
rescue => e
  puts "   ✗ Redis connection error: #{e.message}"
end

# 4. Test DeviceRegistry (your app's Redis usage)
puts "\n4. Testing DeviceRegistry Redis Keys:"
begin
  # Check if DeviceRegistry is working
  active_devices = DeviceRegistry.global_active_set
  puts "   ✓ Active devices set exists: #{active_devices.exists?}"
  puts "   ✓ Active device count: #{active_devices.size}"

  # List some Redis keys
  redis = Kredis.redis
  vpn_keys = redis.keys("vpn9:*")
  puts "   ✓ Total VPN9 keys in Redis: #{vpn_keys.count}"
  puts "   ✓ Sample keys: #{vpn_keys.first(5).join(', ')}" if vpn_keys.any?
rescue => e
  puts "   ✗ DeviceRegistry error: #{e.message}"
end

# 5. Test Redis operations
puts "\n5. Testing Redis Operations:"
begin
  redis = Kredis.redis

  # Test SET/GET
  redis.set("vpn9:test:key", "test_value")
  value = redis.get("vpn9:test:key")
  puts "   ✓ SET/GET test: #{value == 'test_value' ? 'Passed' : 'Failed'}"

  # Test hash operations
  redis.hset("vpn9:test:hash", "field1", "value1")
  hash_value = redis.hget("vpn9:test:hash", "field1")
  puts "   ✓ HASH test: #{hash_value == 'value1' ? 'Passed' : 'Failed'}"

  # Test expiration
  redis.setex("vpn9:test:expiring", 60, "expires_in_60s")
  ttl = redis.ttl("vpn9:test:expiring")
  puts "   ✓ TTL test: Key expires in #{ttl} seconds"

  # Cleanup test keys
  redis.del("vpn9:test:key", "vpn9:test:hash", "vpn9:test:expiring")
  puts "   ✓ Cleanup: Test keys removed"
rescue => e
  puts "   ✗ Operations error: #{e.message}"
end

# 6. Check authentication (if password is set)
puts "\n6. Testing Authentication:"
begin
  redis = Kredis.redis

  # Try to get config (this will fail if auth is required but not provided)
  config = redis.config("get", "requirepass")
  if config["requirepass"].nil? || config["requirepass"].empty?
    puts "   ⚠ No password is set (Redis is unprotected)"
  else
    puts "   ✓ Redis password protection is enabled"
  end
rescue Redis::CommandError => e
  if e.message.include?("NOAUTH")
    puts "   ✓ Authentication is required (good security)"
  else
    puts "   ✗ Config error: #{e.message}"
  end
rescue => e
  puts "   ✗ Auth check error: #{e.message}"
end

puts "\n" + "=" * 60
puts "Redis Connection Test Complete"
puts "=" * 60

# Quick one-liner tests (copy and paste individually):
#
# Kredis.redis.ping
# Kredis.redis.info["redis_version"]
# Kredis.redis.dbsize
# DeviceRegistry.global_active_set.size
# Kredis.redis.keys("vpn9:*").count
