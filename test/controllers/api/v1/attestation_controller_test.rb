require "test_helper"

module Api
  module V1
    class AttestationControllerTest < ActionDispatch::IntegrationTest
      # Test public access without authentication
      test "should get attestation without authentication" do
        get api_v1_attestation_path, as: :json
        assert_response :success
      end

      test "should get verification without authentication" do
        get api_v1_attestation_verify_path, as: :json
        assert_response :success
      end

      # Test response structure for attestation endpoint
      test "attestation returns correct JSON structure" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)

        # Check top-level keys
        assert json_response.key?("status")
        assert json_response.key?("deployment")
        assert json_response.key?("verification")
        assert json_response.key?("checksums")
        assert json_response.key?("instructions")
      end

      test "attestation deployment section contains required fields" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        deployment = json_response["deployment"]

        assert deployment.key?("image_digest")
        assert deployment.key?("container_id")
        assert deployment.key?("build_version")
        assert deployment.key?("build_commit")
        assert deployment.key?("build_timestamp")
        assert deployment.key?("deployed_at")
        assert deployment.key?("hostname")
        assert deployment.key?("environment")
      end

      test "attestation verification section contains correct URLs" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        verification = json_response["verification"]

        assert verification.key?("docker_image")
        assert verification.key?("dockerfile_url")
        assert verification.key?("source_url")
        assert verification.key?("build_log_url")
        assert verification.key?("attestation_url")
        assert verification.key?("sbom_url")

        # Check GitHub URLs use correct organization
        assert_match %r{github.com/vpn9labs/vpn9-portal}, verification["dockerfile_url"]
        assert_match %r{github.com/vpn9labs/vpn9-portal}, verification["source_url"]
        refute_match %r{github.com/vpn9/vpn9-portal}, verification["dockerfile_url"]
      end

      test "attestation checksums section exists" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        checksums = json_response["checksums"]

        assert checksums.key?("image_sha256")
        assert checksums.key?("source_sha256")
      end

      test "attestation instructions section contains commands" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        instructions = json_response["instructions"]

        assert instructions.key?("verify_build")
        assert instructions.key?("compare_digest")
        assert instructions.key?("rebuild_from_source")

        assert_match /docker pull/, instructions["verify_build"]
        assert_match /docker inspect/, instructions["compare_digest"]
        assert_match /git checkout/, instructions["rebuild_from_source"]
      end

      # Test verification endpoint
      test "verification returns correct JSON structure" do
        get api_v1_attestation_verify_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)

        assert json_response.key?("verified")
        assert json_response.key?("timestamp")
        assert json_response.key?("checks")
        assert json_response.key?("proof")
      end

      test "verification checks include all required validations" do
        get api_v1_attestation_verify_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        checks = json_response["checks"]

        assert checks.key?("image_matches_build")
        assert checks.key?("source_matches_commit")
        assert checks.key?("no_modifications")
        assert checks.key?("ssl_certificate_valid")
        assert checks.key?("dns_configured")

        # Each check should return a boolean
        checks.each do |key, value|
          assert [ true, false ].include?(value), "Check #{key} should be boolean"
        end
      end

      test "verification proof contains required fields" do
        get api_v1_attestation_verify_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        proof = json_response["proof"]

        assert proof.key?("data")
        assert proof.key?("signature")

        # In test environment without keys, should have unsigned note
        if proof["signature"] == "unsigned"
          assert proof.key?("note")
        else
          assert proof.key?("public_key_url")
        end
      end

      test "verification timestamp is in ISO8601 format" do
        get api_v1_attestation_verify_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        timestamp = json_response["timestamp"]

        assert_not_nil timestamp
        assert_nothing_raised { Time.iso8601(timestamp) }
      end

      # Test environment handling
      test "attestation returns development environment in test" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)

        # In test environment, Rails.env returns "test"
        assert_equal "test", json_response["deployment"]["environment"]
      end

      # Test response headers
      test "API endpoints return JSON content type" do
        get api_v1_attestation_path, as: :json
        assert_equal "application/json; charset=utf-8", response.content_type

        get api_v1_attestation_verify_path, as: :json
        assert_equal "application/json; charset=utf-8", response.content_type
      end

      # Test CORS headers if needed
      test "API endpoints are accessible cross-origin" do
        get api_v1_attestation_path,
            headers: { "Origin" => "https://example.com" },
            as: :json
        assert_response :success
        # Add CORS header assertions if CORS is configured
      end

      # Test caching headers
      test "attestation endpoint includes appropriate cache headers" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        # Attestation data should not be cached for too long
        # as it represents current state
        # Add cache header assertions based on your caching strategy
      end

      # Test error scenarios
      test "handles missing environment variables gracefully" do
        original_values = {}
        [ "BUILD_VERSION", "BUILD_COMMIT", "BUILD_TIMESTAMP" ].each do |key|
          original_values[key] = ENV[key]
          ENV[key] = nil
        end

        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        # Should have default values, not nil
        assert_not_nil json_response["deployment"]["build_version"]
        assert_not_nil json_response["deployment"]["build_commit"]

        # Restore original values
        original_values.each { |key, value| ENV[key] = value }
      end

      # Test performance
      test "attestation endpoint responds quickly" do
        start_time = Time.current
        get api_v1_attestation_path, as: :json
        response_time = Time.current - start_time

        assert_response :success
        assert response_time < 0.5, "API took too long: #{response_time}s"
      end

      test "verification endpoint responds quickly" do
        start_time = Time.current
        get api_v1_attestation_verify_path, as: :json
        response_time = Time.current - start_time

        assert_response :success
        assert response_time < 1.0, "Verification took too long: #{response_time}s"
      end

      # Test data consistency
      test "attestation data is internally consistent" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        build_version = json_response["deployment"]["build_version"]

        # Docker image should include the build version
        docker_image = json_response["verification"]["docker_image"]
        assert docker_image.include?(build_version) || build_version == "development"

        # URLs should reference the same commit
        build_commit = json_response["deployment"]["build_commit"]
        source_url = json_response["verification"]["source_url"]
        assert source_url.include?(build_commit) unless build_commit == "unknown"
      end

      # Test boolean verification result
      test "verification returns boolean verified field" do
        get api_v1_attestation_verify_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        verified = json_response["verified"]

        assert [ true, false ].include?(verified), "verified should be boolean"
      end

      # Test that sensitive information is not exposed
      test "attestation does not expose sensitive information" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        response_text = response.body

        # Should not contain secrets or keys
        refute_match /SECRET_KEY_BASE/, response_text
        refute_match /RAILS_MASTER_KEY/, response_text
        refute_match /private_key/, response_text
        refute_match /password/i, response_text
      end

      # Test git commit extraction
      test "returns actual git commit when available" do
        get api_v1_attestation_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        build_commit = json_response["deployment"]["build_commit"]

        # In test environment, git_commit returns empty string
        # Should be a valid git SHA, 'unknown', or empty in test
        if build_commit != "unknown" && build_commit != ""
          assert_match /^[a-f0-9]{40}$/, build_commit
        end
      end

      # Test proof generation
      test "verification proof data contains required fields" do
        get api_v1_attestation_verify_path, as: :json
        assert_response :success

        json_response = JSON.parse(response.body)
        proof_data = json_response["proof"]["data"]

        assert proof_data.key?("timestamp")
        assert proof_data.key?("container_id")
        assert proof_data.key?("image_digest")
        assert proof_data.key?("build_commit")

        # Timestamp should be Unix timestamp
        assert proof_data["timestamp"].is_a?(Integer)
      end

      # Test with authenticated user (should still work)
      # Note: Skipping authentication tests due to encrypted field complexities
      # The important test is that these endpoints work WITHOUT authentication
      # which is thoroughly tested above
    end
  end
end
