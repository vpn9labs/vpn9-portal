# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "socket"
require "rbconfig"

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
      Rails.logger.debug("BuildInfo.image_digest: test environment detected, skipping Docker lookup") if defined?(Rails)
      @image_digest = nil
      return @image_digest
    end

    resolver = ImageDigestResolver.new(
      docker_proxy_base_url: docker_proxy_base_url,
      logger: defined?(Rails) ? Rails.logger : nil,
      env: defined?(Rails) ? Rails.env : nil
    )
    @image_digest = resolver.resolve
    Rails.logger.info("BuildInfo.image_digest: resolved actual image digest='#{@image_digest}'") if defined?(Rails) && @image_digest
    @image_digest
  rescue StandardError => e
    Rails.logger.warn("BuildInfo.image_digest: error while resolving image digest: #{e.class} #{e.message}") if defined?(Rails)
    @image_digest = nil
  end

  def expected_image_digest
    return @expected_image_digest if defined?(@expected_image_digest)

    # Avoid network calls in tests
    if Rails.env.test?
      Rails.logger.debug("BuildInfo.expected_image_digest: test environment detected, skipping registry lookup") if defined?(Rails)
      @expected_image_digest = nil
      return @expected_image_digest
    end

    repository = resolve_registry_repository
    tag = version.to_s.presence || "latest"
    Rails.logger.debug("BuildInfo.expected_image_digest: repository='#{repository}', tag='#{tag}'") if defined?(Rails)

    # If running a development build, skip lookup
    if tag == "development"
      Rails.logger.debug("BuildInfo.expected_image_digest: development build detected, skipping registry lookup") if defined?(Rails)
      @expected_image_digest = nil
      return @expected_image_digest
    end

    # Prefer reproducible tag, then version tag, then the container's start tag (unless it's 'latest')
    candidate_tags = []
    candidate_tags << "reproducible-#{tag}"
    candidate_tags << tag
    begin
      start_tag = image_tag
    rescue StandardError
      start_tag = nil
    end
    if start_tag.to_s.present? && start_tag != "latest"
      candidate_tags << start_tag
    end
    candidate_tags = candidate_tags.compact.uniq
    Rails.logger.debug("BuildInfo.expected_image_digest: trying tags in order: #{candidate_tags.join(', ')}") if defined?(Rails)

    resolver = ExpectedImageDigestResolver.new(
      repository: repository,
      candidate_tags: candidate_tags,
      logger: defined?(Rails) ? Rails.logger : nil,
      env: defined?(Rails) ? Rails.env : nil
    )
    result = resolver.resolve
    if result
      @expected_image_digest = result
      Rails.logger.info("BuildInfo.expected_image_digest: resolved expected digest='#{@expected_image_digest}'") if defined?(Rails)
      return @expected_image_digest
    end
    @expected_image_digest = nil
  rescue StandardError => e
    Rails.logger.warn("BuildInfo.expected_image_digest: error while resolving expected digest: #{e.class} #{e.message}") if defined?(Rails)
    @expected_image_digest = nil
  end

  private

  def docker_proxy_base_url
    # Default to the accessory service name reachable inside the app network
    ENV["DOCKER_PROXY_URL"].presence || "http://vpn9-portal-dockerproxy:2375"
  end

  def docker_get_json(path)
    base = docker_proxy_base_url
    uri = URI.join(base.end_with?("/") ? base : base + "/", path.sub(%r{^/}, ""))

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 1.5
    http.read_timeout = 1.5

    request = Net::HTTP::Get.new(uri)
    Rails.logger.debug("BuildInfo.docker_get_json: GET #{uri}") if defined?(Rails)
    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("BuildInfo.docker_get_json: non-success response #{response.code} from #{uri}") if defined?(Rails)
      return nil
    end

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.warn("BuildInfo.docker_get_json: error requesting #{uri}: #{e.class} #{e.message}") if defined?(Rails)
    nil
  end

  def docker_container_id
    # Docker sets the container hostname to the container ID by default
    Socket.gethostname.to_s.strip.presence
  rescue StandardError => e
    Rails.logger.warn("BuildInfo.docker_container_id: error resolving hostname: #{e.class} #{e.message}") if defined?(Rails)
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
        actual.to_s.split("@")[0]
      else
        nil
      end
    end
    repo = repo_from_actual.presence || "ghcr.io/vpn9labs/vpn9-portal"
    Rails.logger.debug("BuildInfo.resolve_registry_repository: using repository='#{repo}', derived_from_actual=#{repo_from_actual.present?}") if defined?(Rails)
    repo
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

    client = GhcrClient.new(path)

    # 1) Try anonymous HEAD
    head_resp = client.head_manifest(tag: tag)
    header_digest = head_resp.is_a?(Net::HTTPSuccess) ? head_resp["Docker-Content-Digest"].to_s.strip.presence : nil

    # If unauthorized, obtain token and retry HEAD
    token = nil
    if head_resp && head_resp.code.to_i == 401
      params = client.parse_bearer_challenge(head_resp["www-authenticate"] || head_resp["WWW-Authenticate"])
      token = client.fetch_bearer_token(params)
      if token.to_s.present?
        auth_head = client.head_manifest(tag: tag, token: token)
        header_digest = auth_head.is_a?(Net::HTTPSuccess) ? auth_head["Docker-Content-Digest"].to_s.strip.presence : header_digest
      end
    end

    # 2) GET manifest (anonymous or with token) to select per-platform digest
    get_resp = client.get_manifest(tag: tag, token: token)
    if get_resp.is_a?(Net::HTTPSuccess)
      digest = extract_digest_from_manifest_response(get_resp)
      return digest if digest.to_s.present?
      # Fallback to header digest
      return (get_resp.each_header.to_h["docker-content-digest"].to_s.strip.presence || header_digest).presence
    end

    # If GET unauthorized and we don't yet have a token, try acquiring one and retry GET
    if get_resp && get_resp.code.to_i == 401 && token.to_s.empty?
      params = client.parse_bearer_challenge(get_resp["www-authenticate"] || get_resp["WWW-Authenticate"])
      token = client.fetch_bearer_token(params)
      if token.to_s.present?
        auth_get = client.get_manifest(tag: tag, token: token)
        if auth_get.is_a?(Net::HTTPSuccess)
          digest = extract_digest_from_manifest_response(auth_get)
          return digest if digest.to_s.present?
          return (auth_get.each_header.to_h["docker-content-digest"].to_s.strip.presence || header_digest).presence
        end
      end
    end
    nil
  rescue StandardError => e
    Rails.logger.warn("BuildInfo.fetch_ghcr_digest: error requesting GHCR for #{repository}:#{tag}: #{e.class} #{e.message}") if defined?(Rails)
    nil
  end

  # Helpers for parsing manifest responses
  def extract_digest_from_manifest_response(response)
    headers = response.each_header.to_h
    body = response.body.to_s
    json = JSON.parse(body) rescue nil
    if json.is_a?(Hash) && json["manifests"].is_a?(Array)
      os, arch = resolve_current_platform
      entry = json["manifests"].find do |m|
        p = m["platform"] || {}
        p["os"].to_s == os.to_s && p["architecture"].to_s == arch.to_s
      end
      return entry["digest"].to_s.strip if entry
    end
    headers["docker-content-digest"].to_s.strip.presence
  end

  # Determine current platform identifiers matching OCI manifest fields
  def resolve_current_platform
    host_os = RbConfig::CONFIG["host_os"].to_s.downcase
    os = host_os.include?("linux") ? "linux" : (host_os.include?("darwin") ? "darwin" : "linux")

    host_cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
    arch = case host_cpu
    when "x86_64", "amd64" then "amd64"
    when "aarch64", "arm64" then "arm64"
    when /^arm/ then "arm"
    else
      "amd64"
    end
    [ os, arch ]
  end

  # Public: Return the tag the container was started with, if available
  # - If the container was started with an @sha digest reference, returns nil
  # - If the container was started with a name without tag, returns "latest"
  def image_tag
    return @image_tag if defined?(@image_tag)

    if Rails.env.test?
      @image_tag = nil
      return @image_tag
    end

    container_id = docker_container_id
    Rails.logger.debug("BuildInfo.image_tag: resolved container_id=#{container_id.to_s[0, 12]}#{container_id && container_id.size > 12 ? '…' : ''}") if defined?(Rails)
    if container_id.nil?
      Rails.logger.warn("BuildInfo.image_tag: no container_id available; running outside Docker?") if defined?(Rails)
      @image_tag = nil
      return @image_tag
    end

    container = docker_get_json("/containers/#{container_id}/json")
    Rails.logger.debug("BuildInfo.image_tag: docker container lookup returned #{container.class}") if defined?(Rails)
    unless container.is_a?(Hash)
      Rails.logger.warn("BuildInfo.image_tag: container metadata missing or invalid") if defined?(Rails)
      @image_tag = nil
      return @image_tag
    end

    ref = container.dig("Config", "Image").to_s
    Rails.logger.debug("BuildInfo.image_tag: Config.Image='#{ref}'") if defined?(Rails)
    @image_tag = extract_tag_from_image_reference(ref)
    Rails.logger.info("BuildInfo.image_tag: start tag='#{@image_tag}'") if defined?(Rails)
    @image_tag
  rescue StandardError => e
    Rails.logger.warn("BuildInfo.image_tag: error while resolving start tag: #{e.class} #{e.message}") if defined?(Rails)
    @image_tag = nil
  end

  # Public: Return the exact image reference the container was started with (e.g., repo:tag or repo@sha)
  def image_start_reference
    return @image_start_reference if defined?(@image_start_reference)

    if Rails.env.test?
      @image_start_reference = nil
      return @image_start_reference
    end

    container_id = docker_container_id
    if container_id.nil?
      @image_start_reference = nil
      return @image_start_reference
    end

    container = docker_get_json("/containers/#{container_id}/json")
    @image_start_reference = container.is_a?(Hash) ? container.dig("Config", "Image").to_s.presence : nil
  rescue StandardError
    @image_start_reference = nil
  end

  # Extract the tag from a full docker image reference without pulling
  # Examples:
  #  - ghcr.io/org/app:reproducible-v1 -> reproducible-v1
  #  - ghcr.io/org/app@sha256:abcd     -> nil
  #  - ghcr.io/org/app                 -> latest
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
end
