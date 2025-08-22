# frozen_string_literal: true

class BuildInfo
  # Public: Value object representing the expected container image digest,
  # resolved from a registry for a given tag policy. Subclass of {ImageDigest}
  # for clarity.
  class ExpectedImageDigest < ImageDigest
  end
end
