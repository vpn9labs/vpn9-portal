# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

#
# GithubReleasesService fetches and normalizes recent GitHub releases
# to power the Transparency Log. It minimizes external calls, caches
# responses, and provides a robust fallback when offline.
#
# Results
# - Returns an Array of Hashes with the following keys:
#   - :version          [String]  release tag/name (e.g., "v1.2.3")
#   - :commit           [String]  7–40 char SHA, if found
#   - :timestamp        [String]  ISO8601 timestamp from published/created
#   - :status           [String]  "active" for current build, otherwise "published"
#   - :attestation_url  [String]  URL to attestation asset or release page
#
class GithubReleasesService
  # Fetch recent builds as normalized entries.
  #
  # In test, never performs network calls and returns a small fallback list.
  # In other environments, caches for 5 minutes.
  #
  # @return [Array<Hash>] see Results
  def self.fetch_builds
    new.fetch_builds
  end

  # Initialize with current BuildInfo (for determining active version).
  # @return [void]
  def initialize
    @build_info = BuildInfo.current
  end

  # Fetch builds from GitHub with caching and fallback behavior.
  # @return [Array<Hash>] see Results
  def fetch_builds
    # Avoid external API calls in test environment
    return fallback_builds if Rails.env.test?

    Rails.cache.fetch("transparency_releases_v1", expires_in: 5.minutes) do
      fetch_from_github
    end
  rescue StandardError
    fallback_builds
  end

  private

  attr_reader :build_info

  # Perform raw GitHub API call and normalize response into releases list.
  # @return [Array<Hash>]
  def fetch_from_github
    uri = URI.parse("https://api.github.com/repos/vpn9labs/vpn9-portal/releases?per_page=10")
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      return fallback_builds
    end

    releases = JSON.parse(response.body)
    builds = Array(releases).map do |rel|
      version = rel["tag_name"].presence || rel["name"].to_s.presence || "unknown"
      body = rel["body"].to_s
      commit = body[/Commit:\s*`?([0-9a-f]{7,40})`?/i, 1].presence || rel["target_commitish"].to_s
      timestamp = rel["published_at"].presence || rel["created_at"].presence || Time.current.iso8601

      asset_url = nil
      if rel["assets"].is_a?(Array)
        asset = rel["assets"].find { |a| a["name"].to_s =~ /\Aattestation-.*\.json\z/ }
        asset_url = asset && asset["browser_download_url"].to_s
      end

      {
        version: version,
        commit: commit,
        timestamp: timestamp,
        status: (version == build_info.version.presence ? "active" : "published"),
        attestation_url: asset_url.presence || rel["html_url"].to_s
      }
    end

    # Sort by timestamp descending (newest first)
    builds.sort_by do |build|
      begin
        Time.parse(build[:timestamp].to_s)
      rescue StandardError
        # Fallback for invalid timestamps
        Time.at(0)
      end
    end.reverse
  end

  # Fallback when offline or errors occur.
  # Provides a minimal list containing the current build as active.
  # @return [Array<Hash>]
  def fallback_builds
    [
      {
        version: Rails.env.test? ? "development" : (build_info.version.presence || "development"),
        commit: build_info.commit.presence || git_commit || "unknown",
        timestamp: build_info.created.presence || Time.current.iso8601,
        status: "active",
        attestation_url: "#"
      }
    ]
  end

  # Resolve git HEAD SHA, except in test where an empty string is returned.
  # @return [String, nil]
  def git_commit
    return "" if Rails.env.test? # Return empty string for test
    `git rev-parse HEAD 2>/dev/null`.strip.presence
  rescue
    nil
  end
end
