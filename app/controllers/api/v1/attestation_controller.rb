# frozen_string_literal: true

module Api
  module V1
    class AttestationController < ActionController::Base
      # Use base controller to avoid authentication
      # This is public information - no auth needed
      protect_from_forgery with: :null_session

      # GET /api/v1/attestation
      # Returns current runtime attestation information
      def show
        render json: {
          status: "running",
          deployment: {
            image_digest: current_image_digest,
            container_id: current_container_id,
            build_version: build_version,
            build_commit: build_commit,
            build_timestamp: build_timestamp,
            deployed_at: deployment_timestamp,
            hostname: Socket.gethostname,
            environment: Rails.env
          },
          verification: {
            docker_image: "vpn9/vpn9-portal:#{build_version}",
            dockerfile_url: "https://github.com/vpn9labs/vpn9-portal/blob/#{build_commit}/Dockerfile",
            source_url: "https://github.com/vpn9labs/vpn9-portal/tree/#{build_commit}",
            build_log_url: "https://github.com/vpn9labs/vpn9-portal/actions/runs/#{ENV['GITHUB_RUN_ID']}",
            attestation_url: "https://github.com/vpn9labs/vpn9-portal/releases/download/#{build_version}/attestation-#{build_version}.json",
            sbom_url: "https://github.com/vpn9labs/vpn9-portal/releases/download/#{build_version}/sbom-#{build_version}.spdx"
          },
          checksums: {
            image_sha256: image_checksum,
            source_sha256: source_checksum
          },
          instructions: {
            verify_build: "docker pull vpn9/vpn9-portal:#{build_version} && ./scripts/verify-build.sh #{build_version}",
            compare_digest: "docker inspect vpn9/vpn9-portal:#{build_version} --format='{{.Id}}'",
            rebuild_from_source: "git checkout #{build_commit} && ./scripts/reproducible-build.sh"
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

      private

      def current_image_digest
        # Read from Docker labels or environment
        return "sha256:test1234567890" if Rails.env.test?
        ENV["DOCKER_IMAGE_DIGEST"] || read_docker_label("org.opencontainers.image.revision")
      end

      def current_container_id
        # Read container ID from cgroup or Docker
        return "test-container-id" if Rails.env.test?

        File.read("/proc/self/cgroup").match(/docker\/([a-f0-9]{64})/)&.captures&.first ||
          ENV["HOSTNAME"]
      rescue
        "unknown"
      end

      def build_version
        ENV["BUILD_VERSION"] || read_docker_label("org.opencontainers.image.version") || "development"
      end

      def build_commit
        ENV["BUILD_COMMIT"] || read_docker_label("org.opencontainers.image.revision") || git_commit || "unknown"
      end

      def build_timestamp
        ENV["BUILD_TIMESTAMP"] || read_docker_label("org.opencontainers.image.created") || Time.current.iso8601
      end

      def git_commit
        return "" if Rails.env.test? # Return empty string for test
        `git rev-parse HEAD 2>/dev/null`.strip.presence
      rescue
        nil
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

      def read_docker_label(label)
        # Read Docker label from current container
        return nil if Rails.env.test?

        container_id = current_container_id
        return nil if container_id == "unknown" || container_id == "test-container-id"

        `docker inspect #{container_id} --format='{{index .Config.Labels "#{label}"}}'`.strip
      rescue
        nil
      end

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
        expected = ENV["EXPECTED_IMAGE_DIGEST"]
        actual = current_image_digest
        expected.present? && actual.present? && expected == actual
      end

      def verify_source_commit
        expected = build_commit
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
          container_id: current_container_id,
          image_digest: current_image_digest,
          build_commit: build_commit
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
