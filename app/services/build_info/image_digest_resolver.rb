# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "socket"

class BuildInfo
  # Internal: Resolves information about the currently running Docker image
  # without mutating global state. Used by {BuildInfo} to fetch the actual image
  # digest as well as auxiliary data like the image tag/reference.
  class ImageDigestResolver
    # @param docker_proxy_base_url [String] base URL to the Docker proxy
    # @param logger [#debug,#warn,nil]
    # @param env [#test?, nil]
    def initialize(docker_proxy_base_url:, logger: nil, env: nil)
      @docker_proxy_base_url = docker_proxy_base_url
      @logger = logger
      @env = env
    end

    # Resolve the running container's image digest via Docker Engine API.
    # @return [BuildInfo::ImageDigest, nil]
    def resolve
      if test_env?
        debug("ImageDigestResolver.resolve: test environment detected, skipping Docker lookup")
        return nil
      end

      container_id = docker_container_id
      debug("ImageDigestResolver.resolve: container_id=#{short(container_id)}")
      return nil if container_id.nil?

      container = docker_get_json("/containers/#{container_id}/json")
      debug("ImageDigestResolver.resolve: container lookup returned #{container.class}")
      return nil unless container.is_a?(Hash)

      image_ref = container["Image"].to_s.presence || container.dig("Config", "Image").to_s
      debug("ImageDigestResolver.resolve: derived image_ref='#{image_ref}'")
      return nil if image_ref.to_s.empty?

      image = docker_get_json("/images/#{URI.encode_www_form_component(image_ref)}/json")
      debug("ImageDigestResolver.resolve: image lookup returned #{image.class}")
      return nil unless image.is_a?(Hash)

      repo_digests = image["RepoDigests"]
      debug("ImageDigestResolver.resolve: RepoDigests count=#{repo_digests.is_a?(Array) ? repo_digests.size : 0}")
      if repo_digests.is_a?(Array) && repo_digests.any?
        preferred = repo_digests.find { |d| d.include?("ghcr.io/") } || repo_digests.first
        BuildInfo::ImageDigest.new(preferred.to_s)
      else
        nil
      end
    rescue StandardError => e
      warn("ImageDigestResolver.resolve: error: #{e.class} #{e.message}")
      nil
    end

    # Public: Return the tag the container was started with, if available
    # - If the container was started with an @sha digest reference, returns nil
    # - If the container was started with a name without tag, returns "latest"
    # @return [String, nil]
    def image_tag
      return nil if test_env?

      container_id = docker_container_id
      debug("ImageDigestResolver.image_tag: container_id=#{short(container_id)}")
      return nil if container_id.nil?

      container = docker_get_json("/containers/#{container_id}/json")
      debug("ImageDigestResolver.image_tag: container lookup returned #{container.class}")
      return nil unless container.is_a?(Hash)

      ref = container.dig("Config", "Image").to_s
      debug("ImageDigestResolver.image_tag: Config.Image='#{ref}'")
      extract_tag_from_image_reference(ref)
    rescue StandardError => e
      warn("ImageDigestResolver.image_tag: error: #{e.class} #{e.message}")
      nil
    end

    # Public: Return the exact image reference the container was started with
    # (e.g., repo:tag or repo@sha)
    # @return [String, nil]
    def image_start_reference
      return nil if test_env?

      container_id = docker_container_id
      return nil if container_id.nil?

      container = docker_get_json("/containers/#{container_id}/json")
      container.is_a?(Hash) ? container.dig("Config", "Image").to_s.presence : nil
    rescue StandardError
      nil
    end

    # Utility used by BuildInfo as a delegator for tests
    # @api private
    # @param path [String]
    # @return [Hash, Array, nil]
    def docker_get_json(path)
      base = @docker_proxy_base_url
      uri = URI.join(base.end_with?("/") ? base : base + "/", path.sub(%r{^/}, ""))

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 1.5
      http.read_timeout = 1.5

      request = Net::HTTP::Get.new(uri)
      debug("ImageDigestResolver.docker_get_json: GET #{uri}")
      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue StandardError => e
      warn("ImageDigestResolver.docker_get_json: error requesting #{path}: #{e.class} #{e.message}")
      nil
    end

    # Utility used by BuildInfo as a delegator for tests
    # @api private
    # @return [String, nil]
    def docker_container_id
      Socket.gethostname.to_s.strip.presence
    rescue StandardError => e
      warn("ImageDigestResolver.docker_container_id: error resolving hostname: #{e.class} #{e.message}")
      nil
    end

    # Extract a tag from a Docker image reference.
    # @param reference [String]
    # @return [String, nil]
    def extract_tag_from_image_reference(reference)
      return nil if reference.to_s.empty?
      return nil if reference.include?("@")

      last_slash = reference.rindex("/")
      last_colon = reference.rindex(":")
      if last_colon && (last_slash.nil? || last_colon > last_slash)
        reference[(last_colon + 1)..-1]
      else
        "latest"
      end
    end

    private

    def test_env?
      !!(@env && @env.respond_to?(:test?) && @env.test?)
    end

    def debug(message)
      @logger&.debug(message)
    end

    def warn(message)
      @logger&.warn(message)
    end

    def short(id)
      return "" if id.to_s.empty?
      "#{id.to_s[0, 12]}#{id && id.size > 12 ? '…' : ''}"
    end
  end
end
