# frozen_string_literal: true

# Ensure build info is present in non-development/test environments
unless Rails.env.development? || Rails.env.test?
  BuildInfo.current
end
