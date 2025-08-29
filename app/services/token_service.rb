require "jwt"

#
# TokenService provides minimal, privacy‑preserving JWT handling.
#
# Principles
# - No tracking, no logging of user activity, no server‑side token storage.
# - Tokens are self‑contained and signed using RS256 (RSA SHA‑256).
# - Only the minimum payload is embedded: subject (user id), expiry/issued‑at,
#   and the user's subscription expiry timestamp for relay‑side checks.
#
# Keys
# - Public/private key material is supplied via `JWT_PUBLIC_KEY`/`JWT_PRIVATE_KEY`
#   environment variables (Base64‑encoded PEM). In development/test, keys are
#   generated on the fly and written under `config/` for convenience.
#
# Usage
#   token = TokenService.generate_token(user)
#   data  = TokenService.verify_token(token)
#   user  = TokenService.authenticate_token(token)
#
# Payload schema (JSON):
# - sub: String           # user id
# - exp: Integer          # expiration (unix epoch seconds)
# - iat: Integer          # issued at (unix epoch seconds)
# - subscription_expires: Integer | nil  # user's subscription expiry
#
class TokenService
  # Token expiration times
  # @return [ActiveSupport::Duration]
  ACCESS_TOKEN_EXPIRY = 24.hours  # Valid for 24 hours

  class << self
    # Generate a signed JWT for a user with an active subscription.
    #
    # @param user [User]
    # @return [String, nil] RS256‑signed JWT string, or nil when user has no active subscription
    # @example
    #   token = TokenService.generate_token(current_user)
    def generate_token(user)
      # Only issue tokens for users with active subscriptions
      return nil unless user.has_active_subscription?

      payload = {
        sub: user.id.to_s,
        exp: ACCESS_TOKEN_EXPIRY.from_now.to_i,
        iat: Time.current.to_i,
        # Include subscription info so relays can verify without callbacks
        subscription_expires: user.current_subscription.expires_at.to_i
      }

      JWT.encode(payload, private_key, "RS256")
    end

    # Verify and decode a JWT.
    #
    # Verifies signature and expiration using the RS256 public key.
    # Returns a minimal, typed hash for app consumption. Does not consult
    # the database; callers decide what to do with the decoded data.
    #
    # @param token [String]
    # @return [Hash, nil] with keys: :user_id (String), :expires_at (Time), :subscription_expires (Time|nil)
    # @example
    #   data = TokenService.verify_token(token)
    #   if data && Time.current < data[:expires_at]
    #     # token structure valid
    #   end
    def verify_token(token)
      payload = JWT.decode(token, public_key, true, { algorithm: "RS256" })

      # Return token data without checking subscription
      # Let the controller decide how to handle subscription status
      {
        user_id: payload[0]["sub"].to_s,
        expires_at: Time.at(payload[0]["exp"]),
        subscription_expires: payload[0]["subscription_expires"] ? Time.at(payload[0]["subscription_expires"]) : nil
      }
    rescue JWT::ExpiredSignature
      nil # Token expired
    rescue JWT::DecodeError
      nil # Invalid token
    end

    # Authenticate by token and return the User record.
    #
    # This resolves the user id from the token and fetches the user from the DB.
    # It does not check subscription state; callers can enforce that policy.
    #
    # @param token [String]
    # @return [User, nil]
    def authenticate_token(token)
      token_data = verify_token(token)
      return nil unless token_data

      User.find_by(id: token_data[:user_id])
    rescue
      nil
    end

    private

    # Load or generate the RSA private key.
    #
    # In production, requires `JWT_PRIVATE_KEY` (Base64‑encoded PEM).
    # In development/test, generates a throwaway key if absent and writes
    # it to `config/jwt_private_key.pem`/`config/jwt_public_key.pem`.
    #
    # @return [OpenSSL::PKey::RSA]
    def private_key
      @private_key ||= begin
        key_content = if ENV["JWT_PRIVATE_KEY"].present?
          Base64.decode64(ENV["JWT_PRIVATE_KEY"])
        else
          generate_keys_if_missing
        end
        OpenSSL::PKey::RSA.new(key_content)
      end
    end

    # Load the RSA public key used for verification.
    #
    # @return [OpenSSL::PKey::RSA]
    def public_key
      @public_key ||= begin
        key_content = if ENV["JWT_PUBLIC_KEY"].present?
          Base64.decode64(ENV["JWT_PUBLIC_KEY"])
        else
          private_key.public_key.to_pem
        end
        OpenSSL::PKey::RSA.new(key_content)
      end
    end

    # Generate throwaway keys for development/test environments.
    #
    # @return [String] PEM‑encoded private key
    # @raise [RuntimeError] when keys are missing in production
    def generate_keys_if_missing
      if Rails.env.development? || Rails.env.test?
        key = OpenSSL::PKey::RSA.generate(2048)

        private_key_path = Rails.root.join("config", "jwt_private_key.pem")
        public_key_path = Rails.root.join("config", "jwt_public_key.pem")

        unless File.exist?(private_key_path)
          File.write(private_key_path, key.to_pem)
          File.write(public_key_path, key.public_key.to_pem)
        end

        key.to_pem
      else
        raise "JWT_PRIVATE_KEY environment variable not set"
      end
    end
  end
end
