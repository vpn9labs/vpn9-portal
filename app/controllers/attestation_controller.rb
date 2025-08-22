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
    GithubReleasesService.fetch_builds
  end
end
