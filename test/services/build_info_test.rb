# frozen_string_literal: true

require "test_helper"

class BuildInfoTest < ActiveSupport::TestCase
  def setup
    @tmp_dir = Rails.root.join("tmp", "build_info_tests")
    FileUtils.mkdir_p(@tmp_dir)
    @original_docker_proxy_url = ENV["DOCKER_PROXY_URL"]
  end

  def teardown
    # Cleanup env vars possibly set by tests
    ENV["DOCKER_PROXY_URL"] = @original_docker_proxy_url
  end

  # Helper to temporarily redefine a class method and restore it after the block
  def with_redefined(klass, method_name, replacement)
    singleton = class << klass; self; end
    original_alias = "__orig_#{method_name}__"
    singleton.send(:alias_method, original_alias, method_name)
    singleton.send(:define_method, method_name, &replacement)
    yield
  ensure
    if singleton.method_defined?(original_alias) || singleton.private_method_defined?(original_alias)
      singleton.send(:alias_method, method_name, original_alias)
      singleton.send(:undef_method, original_alias)
    end
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

  test "image_digest returns nil in test environment (no docker access)" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)
    assert_nil info.image_digest
  end

  test "expected_image_digest returns nil in test environment (no registry lookup)" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)
    assert_nil info.expected_image_digest
  end

  test "loads fs_hash when present in file" do
    path = @tmp_dir.join("with-fs-hash.json").to_s
    File.write(path, { version: "v9.9.9", commit: "deadbeef", created: "2025-08-20T12:34:56Z", fs_hash: "sha256:1234" }.to_json)

    info = BuildInfo.load!(require_file: true, path: path)
    assert_equal "sha256:1234", info.fs_hash
  end

  test "defaults when file invalid JSON and not required" do
    path = @tmp_dir.join("invalid-nonrequired.json").to_s
    File.write(path, "not-json")

    info = BuildInfo.load!(require_file: false, path: path)
    assert_equal "development", info.version
    assert_equal "", info.commit
    assert_match /T/, info.created
    assert_nil info.fs_hash
  end

  test ".current memoizes and .load! replaces the memoized instance" do
    path1 = @tmp_dir.join("b1.json").to_s
    path2 = @tmp_dir.join("b2.json").to_s
    File.write(path1, { version: "v1", commit: "c1", created: "2025-01-01T00:00:00Z" }.to_json)
    File.write(path2, { version: "v2", commit: "c2", created: "2025-02-02T00:00:00Z" }.to_json)

    BuildInfo.load!(require_file: true, path: path1)
    obj1 = BuildInfo.current
    obj1_again = BuildInfo.current
    assert_same obj1, obj1_again
    assert_equal "v1", obj1.version

    BuildInfo.load!(require_file: true, path: path2)
    obj2 = BuildInfo.current
    refute_same obj1, obj2
    assert_equal "v2", obj2.version
  end

  test "docker_proxy_base_url uses env var when set else default" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    ENV["DOCKER_PROXY_URL"] = "http://example:1234"
    assert_equal "http://example:1234", info.send(:docker_proxy_base_url)

    ENV["DOCKER_PROXY_URL"] = nil
    assert_equal "http://vpn9-portal-dockerproxy:2375", info.send(:docker_proxy_base_url)
  end

  test "docker_container_id returns hostname or nil on error" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    with_redefined(Socket, :gethostname, proc { "abcdef" }) do
      assert_equal "abcdef", info.send(:docker_container_id)
    end

    with_redefined(Socket, :gethostname, proc { raise "fail" }) do
      assert_nil info.send(:docker_container_id)
    end
  end

  test "read_first_existing_file picks first non-empty content" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    f1 = @tmp_dir.join("f1.txt").to_s
    f2 = @tmp_dir.join("f2.txt").to_s
    f3 = @tmp_dir.join("f3.txt").to_s

    File.write(f1, "\n\n")
    File.write(f2, "hello")
    File.write(f3, "world")

    result = info.send(:read_first_existing_file, [ f1, f2, f3 ])
    assert_equal "hello", result

    FileUtils.rm_f([ f1, f2, f3 ])
    assert_nil info.send(:read_first_existing_file, [ f1, f2 ])
  end

  test "resolve_registry_repository prefers repo from actual image digest" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    # Force memoized image_digest
    info.instance_variable_set(:@image_digest, "ghcr.io/acme/app@sha256:abcd")
    assert_equal "ghcr.io/acme/app", info.send(:resolve_registry_repository)

    # Clear and fall back to default repo
    info.remove_instance_variable(:@image_digest)
    assert_equal "ghcr.io/vpn9labs/vpn9-portal", info.send(:resolve_registry_repository)
  end

  test "fetch_registry_digest returns nil for non-ghcr repositories" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    assert_nil info.send(:fetch_registry_digest, repository: "docker.io/library/alpine", tag: "latest")
  end

  test "fetch_ghcr_digest returns digest on 200 with header" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    ok = Net::HTTPOK.new("1.1", "200", "OK")
    ok.instance_variable_set(:@read, true)
    ok.instance_variable_set(:@body, "{}")
    def ok.body; @body; end
    def ok.[](header); (@headers ||= {})[header]; end
    def ok.[]=(header, value); (@headers ||= {})[header] = value; end
    def ok.each_header; (@headers ||= {}).each; end
    ok["Docker-Content-Digest"] = "sha256:deadbeef"

    fake_http = Object.new
    def fake_http.use_ssl=(v); end
    def fake_http.open_timeout=(v); end
    def fake_http.read_timeout=(v); end
    fake_http.define_singleton_method(:request) { |_req| ok }

    with_redefined(Net::HTTP, :new, proc { |_host, _port| fake_http }) do
      digest = info.send(:fetch_ghcr_digest, repository: "ghcr.io/acme/app", tag: "1.0.0")
      assert_equal "sha256:deadbeef", digest
    end
  end

  test "fetch_ghcr_digest selects per-platform digest from manifest list" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    # Stub resolve_current_platform to a known pair
    def info.send_resolve_current_platform_for_test
      [ "linux", "amd64" ]
    end
    info.define_singleton_method(:resolve_current_platform) { send_resolve_current_platform_for_test }

    head = Net::HTTPOK.new("1.1", "200", "OK")
    head.instance_variable_set(:@read, true)
    head.instance_variable_set(:@body, "")
    def head.body; @body; end
    def head.[](header); (@headers ||= {})[header]; end
    def head.[]=(header, value); (@headers ||= {})[header] = value; end
    def head.each_header; (@headers ||= {}).each; end

    get = Net::HTTPOK.new("1.1", "200", "OK")
    get.instance_variable_set(:@read, true)
    manifest = {
      "schemaVersion" => 2,
      "manifests" => [
        { "digest" => "sha256:not-this", "platform" => { "os" => "linux", "architecture" => "arm64" } },
        { "digest" => "sha256:pick-me", "platform" => { "os" => "linux", "architecture" => "amd64" } }
      ]
    }.to_json
    get.instance_variable_set(:@body, manifest)
    def get.body; @body; end
    def get.[](header); (@headers ||= {})[header]; end
    def get.[]=(header, value); (@headers ||= {})[header] = value; end
    def get.each_header; (@headers ||= {}).each; end

    # HTTP client that returns head then get
    calls = []
    fake_http = Object.new
    def fake_http.use_ssl=(v); end
    def fake_http.open_timeout=(v); end
    def fake_http.read_timeout=(v); end
    fake_http.define_singleton_method(:request) do |req|
      @__calls ||= 0
      @__calls += 1
      @__calls == 1 ? head : get
    end

    with_redefined(Net::HTTP, :new, proc { |_host, _port| fake_http }) do
      digest = info.send(:fetch_ghcr_digest, repository: "ghcr.io/acme/app", tag: "latest")
      assert_equal "sha256:pick-me", digest
    end
  end

  test "ImageDigest value object behavior" do
    ref = BuildInfo::ImageDigest.new("ghcr.io/acme/app@sha256:abcd")
    assert_equal "ghcr.io/acme/app", ref.repository
    assert_equal "sha256:abcd", ref.digest
    assert_equal "ghcr.io/acme/app@sha256:abcd", ref.to_s
    assert ref == BuildInfo::ExpectedImageDigest.new("ghcr.io/acme/app@sha256:abcd")
    assert ref != BuildInfo::ImageDigest.new("ghcr.io/acme/app@sha256:efef")
  end

  test "extract_digest_from_manifest_response falls back to header" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    resp = Net::HTTPOK.new("1.1", "200", "OK")
    resp.instance_variable_set(:@read, true)
    resp.instance_variable_set(:@body, "{}")
    def resp.body; @body; end
    def resp.[](header); (@headers ||= {})[header]; end
    def resp.[]=(header, value); (@headers ||= {})[header] = value; end
    def resp.each_header; (@headers ||= {}).each; end
    resp["docker-content-digest"] = "sha256:from-header"

    digest = info.send(:extract_digest_from_manifest_response, resp)
    assert_equal "sha256:from-header", digest
  end

  test "docker_get_json returns parsed JSON on success else nil" do
    info = BuildInfo.load!(require_file: false, path: @tmp_dir.join("missing.json").to_s)

    # success path
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    ok.instance_variable_set(:@read, true)
    ok.instance_variable_set(:@body, { a: 1 }.to_json)
    def ok.body; @body; end

    http_ok = Object.new
    def http_ok.open_timeout=(v); end
    def http_ok.read_timeout=(v); end
    http_ok.define_singleton_method(:request) { |_req| ok }

    with_redefined(Net::HTTP, :new, proc { |_host, _port| http_ok }) do
      result = info.send(:docker_get_json, "/anything")
      assert_equal({ "a" => 1 }, result)
    end

    # non-success path
    not_ok = Net::HTTPBadRequest.new("1.1", "400", "Bad")
    not_ok.instance_variable_set(:@read, true)
    not_ok.instance_variable_set(:@body, "bad")
    def not_ok.body; @body; end

    http_bad = Object.new
    def http_bad.open_timeout=(v); end
    def http_bad.read_timeout=(v); end
    http_bad.define_singleton_method(:request) { |_req| not_ok }

    with_redefined(Net::HTTP, :new, proc { |_host, _port| http_bad }) do
      result = info.send(:docker_get_json, "/anything")
      assert_nil result
    end
  end
end
