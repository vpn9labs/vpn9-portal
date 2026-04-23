#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "uri"

DEFAULT_BASE_URL = ENV.fetch("VPN9_API_BASE_URL", "http://localhost:3000")
CLIENT_LABEL = "ruby-relays-client"
TIMEOUT_SECONDS = (ENV["VPN9_API_TIMEOUT"] || 10).to_i

options = {
  base_url: DEFAULT_BASE_URL,
  passphrase: nil
}

parser = OptionParser.new do |opts|
  opts.banner = <<~USAGE
    Usage: api_relays_client.rb [options] --passphrase="word1-word2-..."

    Fetches the list of relays from the VPN9 public API.
  USAGE

  opts.on("-pPASS", "--passphrase=PASS", "Account passphrase (required)") do |pass|
    options[:passphrase] = pass
  end

  opts.on("-bURL", "--base-url=URL", "API base URL (default: #{DEFAULT_BASE_URL})") do |url|
    options[:base_url] = url
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end

parser.parse!(ARGV)

options[:passphrase] = options[:passphrase].to_s.strip
options[:passphrase] = ENV["VPN9_API_PASSPHRASE"] if options[:passphrase].empty?
options[:passphrase] = options[:passphrase].to_s.strip

if options[:passphrase].to_s.strip.empty?
  warn "Error: passphrase missing. Provide via --passphrase or VPN9_API_PASSPHRASE env var."
  warn parser
  exit 1
end

options[:base_url] = options[:base_url].to_s.strip
if options[:base_url].empty?
  warn "Error: base URL cannot be blank"
  exit 1
end

# Ensure trailing slash so URI.join works as expected
base_url = options[:base_url].end_with?("/") ? options[:base_url] : "#{options[:base_url]}/"

TOKEN_PATH = "api/v1/auth/token"
RELAYS_PATH = "api/v1/relays"

def perform_request(uri, request)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.read_timeout = TIMEOUT_SECONDS
  http.open_timeout = TIMEOUT_SECONDS
  http.start do |h|
    h.request(request)
  end
end

def build_uri(base_url, path)
  URI.join(base_url, path)
end

def obtain_access_token(base_url, passphrase)
  uri = build_uri(base_url, TOKEN_PATH)
  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "application/json"
  body = { passphrase: passphrase, client_label: CLIENT_LABEL }
  req.body = JSON.dump(body)

  response = perform_request(uri, req)

  unless response.is_a?(Net::HTTPSuccess)
    raise "Token request failed (#{response.code}): #{response.body}"
  end

  data = JSON.parse(response.body)
  data.fetch("token")
rescue JSON::ParserError
  raise "Unable to parse token response"
end

def fetch_relays(base_url, token)
  uri = build_uri(base_url, RELAYS_PATH)
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Accept"] = "application/json"

  response = perform_request(uri, req)

  unless response.is_a?(Net::HTTPSuccess)
    raise "Relays request failed (#{response.code}): #{response.body}"
  end

  JSON.parse(response.body)
rescue JSON::ParserError
  raise "Unable to parse relays response"
end

begin
  token = obtain_access_token(base_url, options[:passphrase])
  relays = fetch_relays(base_url, token)
  puts JSON.pretty_generate(relays)
rescue StandardError => e
  warn "Error: #{e.message}"
  exit 1
end
