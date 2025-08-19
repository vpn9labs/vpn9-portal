require "jwt"

# JWT token service - NO tracking, NO logging, NO storage
# Tokens are self-contained and verified cryptographically
class TokenService
  # Token expiration times
  ACCESS_TOKEN_EXPIRY = 24.hours  # Valid for 24 hours

  class << self
    # Generate a token for a user with active subscription
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

    # Verify and decode a token
    def verify_token(token)
      payload = JWT.decode(token, public_key, true, { algorithm: "RS256" })

      # Return token data without checking subscription
      # Let the controller decide how to handle subscription status
      {
        user_id: payload[0]["sub"].to_i,
        expires_at: Time.at(payload[0]["exp"]),
        subscription_expires: payload[0]["subscription_expires"] ? Time.at(payload[0]["subscription_expires"]) : nil
      }
    rescue JWT::ExpiredSignature
      nil # Token expired
    rescue JWT::DecodeError
      nil # Invalid token
    end

    # Get user from token (for API authentication)
    def authenticate_token(token)
      token_data = verify_token(token)
      return nil unless token_data

      User.find_by(id: token_data[:user_id])
    rescue
      nil
    end

    private

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
