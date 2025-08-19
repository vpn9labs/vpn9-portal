# frozen_string_literal: true

# Public controller for build attestation and verification
# No authentication required - this is public transparency information
class AttestationController < ApplicationController
  allow_unauthenticated_access

  # GET /verify
  # Public web page showing build verification and transparency dashboard
  def verify
    render :verify, layout: "public"
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

  def fetch_transparency_log
    # In production, this would fetch from GitHub releases or a database
    # For now, return mock data for development
    [
      {
        version: ENV["BUILD_VERSION"] || "development",
        commit: ENV["BUILD_COMMIT"] || git_commit || "unknown",
        timestamp: ENV["BUILD_TIMESTAMP"] || Time.current.iso8601,
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
