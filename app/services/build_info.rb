# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "socket"

class BuildInfo
  BUILD_INFO_PATH = "/usr/share/vpn9/build-info.json"

  def self.current
    @current ||= load!(require_file: !Rails.env.development? && !Rails.env.test?)
  end

  def self.load!(require_file: true, path: BUILD_INFO_PATH)
    @current = new(path: path, require_file: require_file)
  end

  attr_reader :version, :commit, :created, :fs_hash

  def initialize(path:, require_file: true)
    data = read_json_file(path)

    if data.nil?
      if require_file
        raise "Build info file missing at #{path}"
      else
        @version = "development"
        @commit = ""
        @created = Time.current.iso8601
        return
      end
    end

    @version = data["version"].to_s
    @commit = data["commit"].to_s
    @created = data["created"].to_s
    @fs_hash = data["fs_hash"].to_s
  end

  # Resolve the running image's content-addressable digest via Docker Engine API (read-only proxy)
  # Returns a string like "ghcr.io/vpn9labs/vpn9-portal@sha256:..." or nil when unavailable
  def image_digest
    return @image_digest if defined?(@image_digest)

    # Avoid external calls during tests to keep them fast/deterministic
    if Rails.env.test?
      @image_digest = nil
      return @image_digest
    end

    container_id = docker_container_id
    if container_id.nil?
      @image_digest = nil
      return @image_digest
    end

    container = docker_get_json("/containers/#{container_id}/json")
    unless container.is_a?(Hash)
      @image_digest = nil
      return @image_digest
    end

    # Prefer immutable image ID; fall back to configured image name
    image_ref = container["Image"].to_s.presence || container.dig("Config", "Image").to_s
    if image_ref.to_s.empty?
      @image_digest = nil
      return @image_digest
    end

    image = docker_get_json("/images/#{URI.encode_www_form_component(image_ref)}/json")
    unless image.is_a?(Hash)
      @image_digest = nil
      return @image_digest
    end

    repo_digests = image["RepoDigests"]
    if repo_digests.is_a?(Array) && repo_digests.any?
      # If multiple repos are present, prefer our registry host if possible
      preferred = repo_digests.find { |d| d.include?("ghcr.io/") } || repo_digests.first
      @image_digest = preferred.to_s
    else
      @image_digest = nil
    end

    @image_digest
  rescue StandardError
    @image_digest = nil
  end

  def expected_image_digest
    return @expected_image_digest if defined?(@expected_image_digest)

    # Avoid network calls in tests
    if Rails.env.test?
      @expected_image_digest = nil
      return @expected_image_digest
    end

    repository = resolve_registry_repository
    tag = version.to_s.presence || "latest"

    # If running a development build, skip lookup
    if tag == "development"
      @expected_image_digest = nil
      return @expected_image_digest
    end

    digest = fetch_registry_digest(repository: repository, tag: tag)
    @expected_image_digest = digest && "#{repository}@#{digest}"
  rescue StandardError
    @expected_image_digest = nil
  end

  private

  def docker_proxy_base_url
    # Default to the accessory service name reachable inside the app network
    ENV["DOCKER_PROXY_URL"].presence || "http://dockerproxy:2375"
  end

  def docker_get_json(path)
    base = docker_proxy_base_url
    uri = URI.join(base.end_with?("/") ? base : base + "/", path.sub(%r{^/}, ""))

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 1.5
    http.read_timeout = 1.5

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError
    nil
  end

  def docker_container_id
    # Docker sets the container hostname to the container ID by default
    Socket.gethostname.to_s.strip.presence
  rescue StandardError
    nil
  end

  def read_json_file(path)
    return nil unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError
    nil
  end

  def read_first_existing_file(paths)
    paths.each do |path|
      next unless File.exist?(path)
      content = File.read(path).to_s.strip
      return content unless content.empty?
    end
    nil
  end

  # Determine the registry repository to query for expected digest
  # Prefer the repository part from the current image's RepoDigest; fallback to GHCR repo
  def resolve_registry_repository
    repo_from_actual = begin
      actual = image_digest
      if actual.to_s.include?("@")
        actual.split("@")[0]
      else
        nil
      end
    end
    repo_from_actual.presence || "ghcr.io/vpn9labs/vpn9-portal"
  end

  # Fetch the content-addressable digest for a given repo:tag from the container registry
  # Returns a string like "sha256:..." or nil
  def fetch_registry_digest(repository:, tag:)
    # Currently supports GHCR; extend as needed for other registries
    if repository.start_with?("ghcr.io/")
      fetch_ghcr_digest(repository: repository, tag: tag)
    else
      nil
    end
  end

  def fetch_ghcr_digest(repository:, tag:)
    # repository format: ghcr.io/owner/name
    host, path = repository.split("/", 2)
    return nil unless host == "ghcr.io" && path.to_s.present?

    uri = URI.parse("https://ghcr.io/v2/#{path}/manifests/#{URI.encode_www_form_component(tag)}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2.0
    http.read_timeout = 2.0

    request = Net::HTTP::Head.new(uri)
    # Accept both OCI and Docker schema v2 manifests
    request["Accept"] = "application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

    response = http.request(request)
    return nil unless response.is_a?(Net::HTTPSuccess)

    digest = response["Docker-Content-Digest"].to_s.strip
    digest.presence
  rescue StandardError
    nil
  end
end
