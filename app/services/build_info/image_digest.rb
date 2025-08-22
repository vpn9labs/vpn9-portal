# frozen_string_literal: true

class BuildInfo
  class ImageDigest
    attr_reader :reference

    def initialize(reference)
      @reference = reference.to_s
    end

    def repository
      return nil unless reference.include?("@")
      reference.split("@", 2)[0]
    end

    def digest
      return nil unless reference.include?("@")
      reference.split("@", 2)[1]
    end

    def to_s
      reference.to_s
    end

    def as_json(*)
      to_s
    end

    def empty?
      reference.to_s.empty?
    end

    def ==(other)
      to_s == other.to_s
    end
  end
end
