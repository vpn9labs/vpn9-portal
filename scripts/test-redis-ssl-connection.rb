#!/usr/bin/env ruby
# Test Redis SSL/TLS connection
# Run this script to verify Redis SSL configuration is working

require 'redis'
require 'openssl'
require 'optparse'

# Default configuration
options = {
  host: ENV['REDIS_HOST'] || 'localhost',
  port: ENV['REDIS_PORT'] || 6379,
  password: ENV['REDIS_PASSWORD'],
  ssl_ca: 'config/redis-ssl/ca.crt',
  ssl_cert: 'config/redis-ssl/client.crt',
  ssl_key: 'config/redis-ssl/client.key',
  verbose: false
}

# Parse command line arguments
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('-h', '--host HOST', 'Redis host (default: localhost)') do |h|
    options[:host] = h
  end

  opts.on('-p', '--port PORT', Integer, 'Redis port (default: 6379)') do |p|
    options[:port] = p
  end

  opts.on('--password PASSWORD', 'Redis password') do |pass|
    options[:password] = pass
  end

  opts.on('--ca-cert PATH', 'Path to CA certificate') do |path|
    options[:ssl_ca] = path
  end

  opts.on('--client-cert PATH', 'Path to client certificate') do |path|
    options[:ssl_cert] = path
  end

  opts.on('--client-key PATH', 'Path to client private key') do |path|
    options[:ssl_key] = path
  end

  opts.on('-v', '--verbose', 'Verbose output') do
    options[:verbose] = true
  end

  opts.on('--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

def test_connection(options)
  puts "Testing Redis SSL/TLS connection..."
  puts "Host: #{options[:host]}:#{options[:port]}" if options[:verbose]

  # Build SSL parameters
  ssl_params = {
    verify_mode: OpenSSL::SSL::VERIFY_PEER
  }

  # Add CA certificate if it exists
  if File.exist?(options[:ssl_ca])
    ssl_params[:ca_file] = options[:ssl_ca]
    puts "Using CA certificate: #{options[:ssl_ca]}" if options[:verbose]
  else
    puts "Warning: CA certificate not found at #{options[:ssl_ca]}"
  end

  # Add client certificate if it exists
  if File.exist?(options[:ssl_cert])
    ssl_params[:cert] = OpenSSL::X509::Certificate.new(File.read(options[:ssl_cert]))
    puts "Using client certificate: #{options[:ssl_cert]}" if options[:verbose]
  end

  # Add client key if it exists
  if File.exist?(options[:ssl_key])
    ssl_params[:key] = OpenSSL::PKey::RSA.new(File.read(options[:ssl_key]))
    puts "Using client key: #{options[:ssl_key]}" if options[:verbose]
  end

  # Build Redis connection options
  redis_options = {
    host: options[:host],
    port: options[:port],
    ssl: true,
    ssl_params: ssl_params,
    timeout: 5,
    connect_timeout: 5
  }

  # Add password if provided
  redis_options[:password] = options[:password] if options[:password]

  # Attempt connection
  begin
    puts "\nConnecting to Redis with SSL/TLS..." if options[:verbose]
    redis = Redis.new(redis_options)

    # Test basic operations
    puts "\nTesting PING command..."
    response = redis.ping
    puts "✓ PING response: #{response}"

    puts "\nTesting SET/GET commands..."
    test_key = "test:ssl:#{Time.now.to_i}"
    test_value = "SSL connection successful at #{Time.now}"

    redis.set(test_key, test_value)
    puts "✓ SET #{test_key}"

    retrieved = redis.get(test_key)
    puts "✓ GET #{test_key}: #{retrieved}"

    redis.del(test_key)
    puts "✓ DEL #{test_key}"

    # Get server info if verbose
    if options[:verbose]
      puts "\nServer Information:"
      info = redis.info('server')
      puts "  Redis version: #{info['redis_version']}"
      puts "  Redis mode: #{info['redis_mode']}"
      puts "  TCP port: #{info['tcp_port']}"
      puts "  SSL port: #{info['tls_port'] || 'N/A'}"
    end

    # Check SSL/TLS status
    puts "\nSSL/TLS Status:"
    puts "✓ SSL connection established successfully"

    redis.close
    puts "\n✅ All tests passed! Redis SSL/TLS connection is working."
    true

  rescue Redis::CannotConnectError => e
    puts "\n❌ Connection failed: #{e.message}"
    puts "   Make sure Redis is running with SSL/TLS enabled on #{options[:host]}:#{options[:port]}"
    false

  rescue OpenSSL::SSL::SSLError => e
    puts "\n❌ SSL/TLS error: #{e.message}"
    puts "   Check your SSL certificates and configuration"
    false

  rescue => e
    puts "\n❌ Error: #{e.class}: #{e.message}"
    puts e.backtrace.first(5) if options[:verbose]
    false
  end
end

def test_non_ssl_connection(options)
  puts "\nTesting non-SSL connection for comparison..."

  begin
    redis = Redis.new(
      host: options[:host],
      port: 6379,  # Try standard Redis port
      password: options[:password],
      timeout: 2,
      connect_timeout: 2
    )
    redis.ping
    puts "⚠️  Non-SSL connection succeeded on port 6379"
    puts "   Consider disabling non-SSL access for security"
    redis.close
  rescue
    puts "✓ Non-SSL connection failed (as expected with SSL-only configuration)"
  end
end

# Run tests
success = test_connection(options)
test_non_ssl_connection(options) if options[:verbose]

exit(success ? 0 : 1)
