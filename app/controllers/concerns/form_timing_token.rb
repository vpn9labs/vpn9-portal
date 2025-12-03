# frozen_string_literal: true

# Provides HMAC-signed timing tokens for anti-bot protection.
# Tokens are generated server-side to prevent client-side spoofing.
module FormTimingToken
  extend ActiveSupport::Concern

  MINIMUM_FORM_TIME_SECONDS = 2.5
  TOKEN_MAX_AGE_SECONDS = 3600 # 1 hour max token age

  private

  # Generate a signed timing token for embedding in forms
  def generate_form_timing_token
    timestamp = Time.current.to_f.to_s
    signature = form_timing_signature(timestamp)
    "#{timestamp}--#{signature}"
  end

  # Verify the token and check if submission was too fast
  # Returns true if submission should be rejected (too fast or invalid)
  def too_fast_submission?
    return false if Rails.env.test? && !ENV["TEST_TIMING_VALIDATION"]

    form_token = params[:form_token]
    if form_token.blank?
      Rails.logger.info("[AntiBot] Missing form_token - JS disabled or bypass attempt")
      return false # Graceful degradation for JS-disabled users
    end

    timestamp, signature = form_token.to_s.split("--", 2)
    if timestamp.blank? || signature.blank?
      Rails.logger.info("[AntiBot] Malformed form_token - missing timestamp or signature")
      return true
    end

    # Verify signature
    unless secure_compare(signature, form_timing_signature(timestamp))
      Rails.logger.info("[AntiBot] Invalid form_token signature - possible tampering")
      return true
    end

    # Check timing
    loaded_at = timestamp.to_f
    elapsed_seconds = Time.current.to_f - loaded_at

    # Reject if too old (prevents token reuse attacks)
    return true if elapsed_seconds > TOKEN_MAX_AGE_SECONDS

    # Reject if too fast
    elapsed_seconds < MINIMUM_FORM_TIME_SECONDS
  rescue ArgumentError => e
    Rails.logger.info("[AntiBot] form_token parsing error: #{e.message}")
    true # Reject malformed tokens
  end

  def form_timing_signature(timestamp)
    OpenSSL::HMAC.hexdigest(
      "SHA256",
      Rails.application.secret_key_base,
      "form_timing:#{timestamp}"
    )
  end

  def secure_compare(a, b)
    ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
  end
end
