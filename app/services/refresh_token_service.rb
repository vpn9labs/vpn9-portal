class RefreshTokenService
  TOKEN_BYTES = 32
  TOKEN_TTL = 45.days
  MAX_ACTIVE_TOKENS_PER_USER = 5

  class << self
    def issue_for(user, client_label: nil)
      return nil unless user&.active?
      return nil unless user.has_active_subscription?

      raw_token = generate_raw_token
      digest = ApiRefreshToken.digest(raw_token)

      record = user.api_refresh_tokens.create!(
        token_hash: digest,
        expires_at: TOKEN_TTL.from_now,
        client_label: client_label,
        last_used_at: Time.current
      )

      prune_excess_tokens_for(user)

      { token: raw_token, record: record }
    end

    def exchange(raw_token)
      return nil if raw_token.blank?

      digest = ApiRefreshToken.digest(raw_token)
      record = ApiRefreshToken.find_by(token_hash: digest)
      return nil unless record

      record.with_lock do
        return invalidate!(record) if record.expired?

        user = record.user
        return invalidate!(record) unless user&.active? && user.has_active_subscription?

        new_raw_token = generate_raw_token
        record.update!(
          token_hash: ApiRefreshToken.digest(new_raw_token),
          expires_at: TOKEN_TTL.from_now,
          last_used_at: Time.current,
          usage_count: record.usage_count.to_i + 1
        )

        prune_excess_tokens_for(user)

        { user: user, refresh_token: new_raw_token }
      end
    end

    def revoke_for_user!(user)
      return unless user

      user.api_refresh_tokens.delete_all
    end

    def revoke!(raw_token)
      digest = ApiRefreshToken.digest(raw_token)
      ApiRefreshToken.where(token_hash: digest).delete_all
    end

    private

    def generate_raw_token
      SecureRandom.urlsafe_base64(TOKEN_BYTES)
    end

    def prune_excess_tokens_for(user)
      tokens = user.api_refresh_tokens.order(last_used_at: :desc, created_at: :desc)
      return if tokens.count <= MAX_ACTIVE_TOKENS_PER_USER

      tokens.offset(MAX_ACTIVE_TOKENS_PER_USER).destroy_all
    end

    def invalidate!(record)
      record.destroy!
      nil
    end
  end
end
