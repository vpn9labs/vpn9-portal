# frozen_string_literal: true

# Public controller for build attestation and verification
# No authentication required - this is public transparency information
class AttestationController < ApplicationController
  allow_unauthenticated_access

  # GET /attestation
  # Public web page showing build verification and transparency dashboard
  def show
    render :show, layout: "public"
  end

  # GET /transparency
  # Transparency log page showing all historical builds
  def transparency
    @builds = fetch_transparency_log
    render :transparency, layout: "public"
  end

  # GET /security
  # Security and verification documentation
  def security
    render :security, layout: "public"
  end

  private

  def build_info
    BuildInfo.current
  end

  def fetch_transparency_log
    # Avoid external API calls in test environment
    return fallback_transparency_log if Rails.env.test?

    Rails.cache.fetch("transparency_releases_v1", expires_in: 5.minutes) do
      uri = URI.parse("https://api.github.com/repos/vpn9labs/vpn9-portal/releases?per_page=10")
      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        return fallback_transparency_log
      end

      releases = JSON.parse(response.body)
      Array(releases).map do |rel|
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
    rescue StandardError
      fallback_transparency_log
    end
  end

  def fallback_transparency_log
    [
      {
        version: build_info.version.presence || "development",
        commit: build_info.commit.presence || git_commit || "unknown",
        timestamp: build_info.created.presence || Time.current.iso8601,
        status: "active",
        attestation_url: "#"
      }
    ]
  end

  def git_commit
    `git rev-parse HEAD 2>/dev/null`.strip.presence
  rescue
    nil
  end
end
