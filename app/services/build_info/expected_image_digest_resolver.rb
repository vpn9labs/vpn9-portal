# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "rbconfig"

class BuildInfo
  # Internal: Resolves the expected image digest from a container registry
  # given a repository and a set of candidate tags. Keeps all registry-specific
  # logic here to keep BuildInfo small.
  class ExpectedImageDigestResolver
    def initialize(repository:, candidate_tags:, logger: nil, env: nil)
      @repository = repository
      @candidate_tags = Array(candidate_tags).compact.uniq
      @logger = logger
      @env = env
    end

    # Returns BuildInfo::ExpectedImageDigest or nil
    def resolve
      if test_env?
        debug("ExpectedImageDigestResolver.resolve: test environment detected, skipping registry lookup")
        return nil
      end

      return nil if @candidate_tags.empty?

      @candidate_tags.each do |tag|
        digest = fetch_registry_digest(repository: @repository, tag: tag)
        if digest.to_s.present?
          debug("ExpectedImageDigestResolver.resolve: found digest for tag='#{tag}'")
          return BuildInfo::ExpectedImageDigest.new("#{@repository}@#{digest}")
        else
          warn("ExpectedImageDigestResolver.resolve: no digest for #{@repository}:#{tag}")
        end
      end
      nil
    rescue StandardError => e
      warn("ExpectedImageDigestResolver.resolve: error: #{e.class} #{e.message}")
      nil
    end

    # Public: Registry digest for repo:tag (e.g., 'sha256:abcd') or nil
    def fetch_registry_digest(repository:, tag:)
      if repository.start_with?("ghcr.io/")
        fetch_ghcr_digest(repository: repository, tag: tag)
      else
        nil
      end
    end

    def fetch_ghcr_digest(repository:, tag:)
      host, path = repository.split("/", 2)
      return nil unless host == "ghcr.io" && path.to_s.present?

      client = BuildInfo::GhcrClient.new(path)

      head_resp = client.head_manifest(tag: tag)
      header_digest = head_resp.is_a?(Net::HTTPSuccess) ? head_resp["Docker-Content-Digest"].to_s.strip.presence : nil

      token = nil
      if head_resp && head_resp.code.to_i == 401
        params = client.parse_bearer_challenge(head_resp["www-authenticate"] || head_resp["WWW-Authenticate"])
        token = client.fetch_bearer_token(params)
        if token.to_s.present?
          auth_head = client.head_manifest(tag: tag, token: token)
          header_digest = auth_head.is_a?(Net::HTTPSuccess) ? auth_head["Docker-Content-Digest"].to_s.strip.presence : header_digest
        end
      end

      get_resp = client.get_manifest(tag: tag, token: token)
      if get_resp.is_a?(Net::HTTPSuccess)
        digest = extract_digest_from_manifest_response(get_resp)
        return digest if digest.to_s.present?
        return (get_resp.each_header.to_h["docker-content-digest"].to_s.strip.presence || header_digest).presence
      end

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
      warn("ExpectedImageDigestResolver.fetch_ghcr_digest: error for #{repository}:#{tag}: #{e.class} #{e.message}")
      nil
    end

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
  end
end
