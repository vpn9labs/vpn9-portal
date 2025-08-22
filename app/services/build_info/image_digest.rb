# frozen_string_literal: true

class BuildInfo
  # Public: Value object representing a container image reference pinned to a
  # content-addressable digest, in the form `repository@sha256:...`.
  #
  # @!attribute [r] reference
  #   Full reference string including repository and digest.
  #   @return [String]
  class ImageDigest
    attr_reader :reference

    # @param reference [String] full reference (e.g., "ghcr.io/org/app@sha256:abcd")
    # @return [void]
    def initialize(reference)
      @reference = reference.to_s
    end

    # Repository part of the reference (left of `@`).
    # @return [String, nil]
    def repository
      return nil unless reference.include?("@")
      reference.split("@", 2)[0]
    end

    # Digest part of the reference (right of `@`).
    # @return [String, nil]
    def digest
      return nil unless reference.include?("@")
      reference.split("@", 2)[1]
    end

    # String representation of the reference.
    # @return [String]
    def to_s
      reference.to_s
    end

    # JSON representation used by serializers.
    # @return [String]
    def as_json(*)
      to_s
    end

    # Whether the reference is empty.
    # @return [Boolean]
    def empty?
      reference.to_s.empty?
    end

    # Equality based on string representation.
    # @param other [#to_s]
    # @return [Boolean]
    def ==(other)
      to_s == other.to_s
    end
  end
end
