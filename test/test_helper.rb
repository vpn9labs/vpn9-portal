ENV["RAILS_ENV"] ||= "test"

# Set up encryption keys for test environment if not already set
ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||= "test_primary_key_32_chars_minimum"
ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||= "test_deterministic_key_32_chars_min"
ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||= "test_key_derivation_salt_32_chars"

# Set up JWT keys for test environment if not already set
if ENV["JWT_PRIVATE_KEY"].nil?
  require "openssl"
  require "base64"
  key = OpenSSL::PKey::RSA.generate(2048)
  ENV["JWT_PRIVATE_KEY"] = Base64.encode64(key.to_pem)
  ENV["JWT_PUBLIC_KEY"] = Base64.encode64(key.public_key.to_pem)
end

require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

# Ensure Geocoder never makes external calls in tests
# Use the in-memory test lookup with a fast timeout and a safe default stub
Geocoder.configure(
  lookup: :test,
  ip_lookup: :test,
  timeout: 0.01
)
Geocoder::Lookup::Test.set_default_stub([
  {
    "coordinates" => [ 50.0, 10.0 ],
    "latitude" => 50.0,
    "longitude" => 10.0,
    "country" => "Test Country"
  }
])

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
