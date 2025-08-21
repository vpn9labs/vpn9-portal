# frozen_string_literal: true

require "test_helper"

class BuildInfoTest < ActiveSupport::TestCase
  def setup
    @tmp_dir = Rails.root.join("tmp", "build_info_tests")
    FileUtils.mkdir_p(@tmp_dir)

    # Save originals to restore after tests that override constants
    @orig_image_paths = BuildInfo::IMAGE_DIGEST_PATHS.dup
    @orig_expected_paths = BuildInfo::EXPECTED_IMAGE_DIGEST_PATHS.dup
  end

  def teardown
    # Restore constants if changed
    BuildInfo.send(:remove_const, :IMAGE_DIGEST_PATHS)
    BuildInfo.const_set(:IMAGE_DIGEST_PATHS, @orig_image_paths.freeze)

    BuildInfo.send(:remove_const, :EXPECTED_IMAGE_DIGEST_PATHS)
    BuildInfo.const_set(:EXPECTED_IMAGE_DIGEST_PATHS, @orig_expected_paths.freeze)

    # Cleanup env vars possibly set by tests
    %w[DOCKER_IMAGE_DIGEST EXPECTED_IMAGE_DIGEST].each { |k| ENV.delete(k) }
  end

  test "loads version, commit, created from provided file path" do
    path = @tmp_dir.join("build-info.json").to_s
    File.write(path, { version: "v1.2.3", commit: "abc123", created: "2025-08-20T12:34:56Z" }.to_json)

    info = BuildInfo.load!(require_file: true, path: path)

    assert_equal "v1.2.3", info.version
    assert_equal "abc123", info.commit
    assert_equal "2025-08-20T12:34:56Z", info.created
  end

  test "returns defaults in test when file missing and not required" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)
    assert_equal "development", info.version
    assert_equal "", info.commit
    assert_match /T/, info.created # ISO8601-like
  end

  test "raises when file missing and required" do
    assert_raises RuntimeError do
      BuildInfo.load!(require_file: true, path: @tmp_dir.join("missing.json").to_s)
    end
  end

  test "raises when file invalid JSON and required" do
    path = @tmp_dir.join("invalid.json").to_s
    File.write(path, "{ invalid json")
    assert_raises RuntimeError do
      BuildInfo.load!(require_file: true, path: path)
    end
  end

  test "image_digest prefers file over env" do
    # Point digest paths to temp file
    image_path = @tmp_dir.join("image-digest").to_s
    File.write(image_path, "sha256:file_digest")

    BuildInfo.send(:remove_const, :IMAGE_DIGEST_PATHS)
    BuildInfo.const_set(:IMAGE_DIGEST_PATHS, [ image_path ].freeze)

    ENV["DOCKER_IMAGE_DIGEST"] = "sha256:env_digest"

    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)
    assert_equal "sha256:file_digest", info.image_digest
  end

  test "image_digest falls back to env when no file" do
    BuildInfo.send(:remove_const, :IMAGE_DIGEST_PATHS)
    BuildInfo.const_set(:IMAGE_DIGEST_PATHS, [ @tmp_dir.join("nonexistent").to_s ].freeze)

    ENV["DOCKER_IMAGE_DIGEST"] = "sha256:env_digest"

    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)
    assert_equal "sha256:env_digest", info.image_digest
  end

  test "expected_image_digest prefers file over env" do
    expected_path = @tmp_dir.join("expected-image-digest").to_s
    File.write(expected_path, "sha256:expected_file")

    BuildInfo.send(:remove_const, :EXPECTED_IMAGE_DIGEST_PATHS)
    BuildInfo.const_set(:EXPECTED_IMAGE_DIGEST_PATHS, [ expected_path ].freeze)

    ENV["EXPECTED_IMAGE_DIGEST"] = "sha256:expected_env"

    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)
    assert_equal "sha256:expected_file", info.expected_image_digest
  end

  test "expected_image_digest falls back to env when no file" do
    BuildInfo.send(:remove_const, :EXPECTED_IMAGE_DIGEST_PATHS)
    BuildInfo.const_set(:EXPECTED_IMAGE_DIGEST_PATHS, [ @tmp_dir.join("nonexistent").to_s ].freeze)

    ENV["EXPECTED_IMAGE_DIGEST"] = "sha256:expected_env"

    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)
    assert_equal "sha256:expected_env", info.expected_image_digest
  end
end
