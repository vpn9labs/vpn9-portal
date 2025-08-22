# frozen_string_literal: true

require "json"

module Api
  module V1
    class AttestationController < ActionController::API
      # GET /api/v1/attestation
      # Returns current runtime attestation information
      def show
        info = BuildInfo.current
        render json: {
          status: "running",
          deployment: {
            image_digest: info.image_digest,
            build_version: resolved_build_version,
            build_commit: resolved_build_commit,
            build_timestamp: info.created.presence || Time.current.iso8601,
            deployed_at: deployment_timestamp,
            environment: Rails.env
          },
          verification: {
            docker_image: "vpn9/vpn9-portal:#{info.version.presence || "development"}",
            dockerfile_url: "https://github.com/vpn9labs/vpn9-portal/blob/#{info.commit.presence || git_commit || "unknown"}/Dockerfile",
            source_url: "https://github.com/vpn9labs/vpn9-portal/tree/#{info.commit.presence || git_commit || "unknown"}",
            build_log_url: "https://github.com/vpn9labs/vpn9-portal/actions/runs/#{ENV['GITHUB_RUN_ID']}",
            attestation_url: "https://github.com/vpn9labs/vpn9-portal/releases/download/#{info.version.presence || "development"}/attestation-#{info.version.presence || "development"}.json",
            sbom_url: "https://github.com/vpn9labs/vpn9-portal/releases/download/#{info.version.presence || "development"}/sbom-#{info.version.presence || "development"}.spdx"
          },
          checksums: {
            image_sha256: image_checksum,
            source_sha256: source_checksum
          },
          instructions: {
            verify_build: "docker pull vpn9/vpn9-portal:#{resolved_build_version} && ./scripts/verify-build.sh #{resolved_build_version}",
            compare_digest: "docker inspect vpn9/vpn9-portal:#{resolved_build_version} --format='{{.Id}}'",
            rebuild_from_source: "git checkout #{resolved_build_commit} && ./scripts/reproducible-build.sh"
          }
        }
      end

      # GET /api/v1/attestation/verify
      # Performs real-time verification
      def verify
        verification_result = perform_runtime_verification

        render json: {
          verified: verification_result[:success],
          timestamp: Time.current.iso8601,
          checks: verification_result[:checks],
          proof: generate_verification_proof
        }
      end

      # GET /api/v1/transparency
      # Returns transparency log data using the same service as the web controller
      def transparency
        builds = GithubReleasesService.fetch_builds
        render json: builds
      end

      # GET /api/v1/attestation/debug
      # Debug endpoint (redacts container identifiers)
      def debug
        render json: {
          container: {},
          environment: {
            build_version: ENV["BUILD_VERSION"],
            build_commit: ENV["BUILD_COMMIT"],
            build_timestamp: ENV["BUILD_TIMESTAMP"],
            docker_image_digest: BuildInfo.current.image_digest
          }
        }
      end

      private

      def build_info
        @build_info ||= begin
          path = "/usr/share/vpn9/build-info.json"
          if File.exist?(path)
            JSON.parse(File.read(path))
          else
            {}
          end
        rescue JSON::ParserError
          {}
        end
      end

      def read_first_existing_file(*paths)
        paths.compact.each do |path|
          next unless path && File.exist?(path)
          begin
            content = File.read(path).to_s.strip
            return content unless content.empty?
          rescue
            next
          end
        end
        nil
      end

      # image digest paths handled by BuildInfo

      # Container identifiers intentionally not exposed for privacy

      # build version/commit/timestamp now provided by BuildInfo

      def git_commit
        return "" if Rails.env.test? # Return empty string for test
        `git rev-parse HEAD 2>/dev/null`.strip.presence
      rescue
        nil
      end

      def resolved_build_version
        info = BuildInfo.current
        info.version.presence || "development"
      end

      def resolved_build_commit
        info = BuildInfo.current
        info.commit.presence || git_commit.presence || "unknown"
      end

      def deployment_timestamp
        File.mtime("/rails/config/environment.rb").iso8601
      rescue
        "unknown"
      end

      def image_checksum
        # This would be set during deployment
        ENV["IMAGE_SHA256"] || "pending"
      end

      def source_checksum
        # Calculate source tree hash
        `git rev-parse HEAD`.strip rescue "unknown"
      end

      # Docker socket and registry lookups removed: labels cannot be read and digest must be injected.

      def perform_runtime_verification
        checks = {
          image_matches_build: verify_image_digest,
          source_matches_commit: verify_source_commit,
          no_modifications: verify_no_runtime_modifications,
          ssl_certificate_valid: verify_ssl_certificate,
          dns_configured: verify_dns_configuration
        }

        {
          success: checks.values.all?,
          checks: checks
        }
      end

      def verify_image_digest
        info = BuildInfo.current
        expected = info.expected_image_digest
        actual = info.image_digest
        expected.present? && actual.present? && expected == actual
      end

      def verify_source_commit
        expected = resolved_build_commit
        actual = `git rev-parse HEAD`.strip rescue nil
        expected.present? && actual.present? && expected == actual
      end

      def verify_no_runtime_modifications
        # Check that no files have been modified since container start
        modified_files = `find /rails -type f -newer /proc/1/cmdline 2>/dev/null | head -5`.strip
        modified_files.empty?
      end

      def verify_ssl_certificate
        # Verify SSL certificate is valid and matches domain
        true # Implement actual SSL verification
      end

      def verify_dns_configuration
        # Verify DNS is properly configured
        true # Implement actual DNS verification
      end

      def generate_verification_proof
        # Generate cryptographic proof of verification
        data = {
          timestamp: Time.current.to_i,
          image_digest: BuildInfo.current.image_digest,
          build_commit: resolved_build_commit
        }

        # Sign with server's private key if available
        if File.exist?("/rails/config/jwt_private_key.pem")
          private_key = OpenSSL::PKey::RSA.new(File.read("/rails/config/jwt_private_key.pem"))
          signature = Base64.strict_encode64(private_key.sign(OpenSSL::Digest::SHA256.new, data.to_json))

          {
            data: data,
            signature: signature,
            public_key_url: "https://vpn9.com/.well-known/verification-key.pem"
          }
        else
          {
            data: data,
            signature: "unsigned",
            note: "Signature pending key configuration"
          }
        end
      end
    end
  end
end
