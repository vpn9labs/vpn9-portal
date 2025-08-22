# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class BuildInfo
  # Internal: Minimal client for GitHub Container Registry manifest endpoints.
  # Provides HEAD/GET for manifests and utilities for WWW-Authenticate handling.
  class GhcrClient
    ACCEPT_HEADER = [
      "application/vnd.oci.image.manifest.v1+json",
      "application/vnd.docker.distribution.manifest.v2+json",
      "application/vnd.oci.image.index.v1+json",
      "application/vnd.docker.distribution.manifest.list.v2+json"
    ].join(", ")

    # @param repository_path [String] the path portion of the repository,
    #   e.g., "owner/name"
    def initialize(repository_path)
      @repository_path = repository_path
    end

    # Perform HEAD request for a manifest.
    # @param tag [String]
    # @param token [String, nil]
    # @return [Net::HTTPResponse]
    def head_manifest(tag:, token: nil)
      uri = manifest_uri(tag)
      http = build_http(uri)
      request = Net::HTTP::Head.new(uri)
      request["Accept"] = ACCEPT_HEADER
      request["Authorization"] = "Bearer #{token}" if token.to_s.present?
      http.request(request)
    end

    # Perform GET request for a manifest or manifest list.
    # @param tag [String]
    # @param token [String, nil]
    # @return [Net::HTTPResponse]
    def get_manifest(tag:, token: nil)
      uri = manifest_uri(tag)
      http = build_http(uri)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = ACCEPT_HEADER
      request["Authorization"] = "Bearer #{token}" if token.to_s.present?
      http.request(request)
    end

    # Fetch an OAuth2 bearer token per the registry's WWW-Authenticate challenge.
    # @param params [Hash{String=>String}] keys like "realm", "service", "scope"
    # @return [String, nil]
    def fetch_bearer_token(params)
      realm = params["realm"].to_s
      return nil if realm.empty?
      service = params["service"].to_s
      scope = params["scope"].to_s

      uri = URI.parse(realm)
      uri.query = URI.encode_www_form({ service: service, scope: scope }.compact)

      http = build_http(uri)
      response = http.request(Net::HTTP::Get.new(uri))
      return nil unless response.is_a?(Net::HTTPSuccess)
      body = JSON.parse(response.body) rescue {}
      body["token"].to_s.presence || body["access_token"].to_s.presence
    rescue StandardError
      nil
    end

    # Parse a WWW-Authenticate bearer challenge header into key/value pairs.
    # @param header [String]
    # @return [Hash{String=>String}]
    def parse_bearer_challenge(header)
      return {} if header.to_s.empty?
      value = header.to_s
      value = value.split(/\s+/, 2)[1] || value
      pairs = value.scan(/(\w+)="([^"]*)"/)
      Hash[pairs]
    rescue StandardError
      {}
    end

    private

    # @api private
    # @param tag [String]
    # @return [URI::HTTPS]
    def manifest_uri(tag)
      URI.parse("https://ghcr.io/v2/#{@repository_path}/manifests/#{URI.encode_www_form_component(tag)}")
    end

    # @api private
    # @param uri [URI]
    # @return [Net::HTTP]
    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 2.0
      http.read_timeout = 2.0
      http
    end
  end
end
