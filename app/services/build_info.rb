# frozen_string_literal: true

require "json"

class BuildInfo
  BUILD_INFO_PATH = "/usr/share/vpn9/build-info.json"
  IMAGE_DIGEST_PATHS = [
    "/run/image-digest",
    "/run/secrets/image-digest",
    "/var/run/secrets/image-digest"
  ].freeze
  EXPECTED_IMAGE_DIGEST_PATHS = [
    "/run/expected-image-digest",
    "/run/secrets/expected-image-digest",
    "/var/run/secrets/expected-image-digest"
  ].freeze

  def self.current
    @current ||= load!(require_file: !Rails.env.development? && !Rails.env.test?)
  end

  def self.load!(require_file: true, path: BUILD_INFO_PATH)
    @current = new(path: path, require_file: require_file)
  end

  attr_reader :version, :commit, :created

  def initialize(path:, require_file: true)
    data = read_json_file(path)

    if data.nil?
      if require_file
        raise "Build info file missing at #{path}"
      else
        @version = "development"
        @commit = ""
        @created = Time.current.iso8601
        return
      end
    end

    @version = data["version"].to_s
    @commit = data["commit"].to_s
    @created = data["created"].to_s
  end

  def image_digest
    read_first_existing_file(IMAGE_DIGEST_PATHS) || ENV["DOCKER_IMAGE_DIGEST"]
  end

  def expected_image_digest
    read_first_existing_file(EXPECTED_IMAGE_DIGEST_PATHS) || ENV["EXPECTED_IMAGE_DIGEST"]
  end

  private

  def read_json_file(path)
    return nil unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError
    nil
  end

  def read_first_existing_file(paths)
    paths.each do |path|
      next unless File.exist?(path)
      content = File.read(path).to_s.strip
      return content unless content.empty?
    end
    nil
  end
end
