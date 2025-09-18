class Api::V1::AuthController < ActionController::API
  # POST /api/v1/auth/token
  # Get a token for VPN access - NO tracking, NO logging
  def token
    passphrase = params[:passphrase]
    client_label = params[:client_label]

    if passphrase.blank?
      render json: { error: "Missing passphrase" }, status: :bad_request
      return
    end

    # Authenticate user
    user = User.authenticate_by_passphrase(passphrase)

    unless user
      render json: { error: "Invalid passphrase" }, status: :unauthorized
      return
    end

    unless user.active?
      render json: { error: "Account inactive" }, status: :forbidden
      return
    end

    # Check subscription
    unless user.has_active_subscription?
      render json: {
        error: "No active subscription",
        subscription_required: true
      }, status: :payment_required
      return
    end

    # Generate token
    token = TokenService.generate_token(user)

    unless token
      render json: { error: "Failed to generate token" }, status: :internal_server_error
      return
    end

    refresh_token_payload = RefreshTokenService.issue_for(user, client_label: client_label)

    unless refresh_token_payload
      render json: { error: "Failed to issue refresh token" }, status: :internal_server_error
      return
    end

    subscription = user.current_subscription

    # Return token with minimal information
    render json: {
      token: token,
      refresh_token: refresh_token_payload[:token],
      expires_in: TokenService::ACCESS_TOKEN_EXPIRY.to_i,
      subscription_expires_at: subscription&.expires_at
    }
  end

  # GET /api/v1/auth/verify
  # Verify a token is valid (for testing/debugging)
  def verify
    auth_header = request.headers["Authorization"]

    unless auth_header&.start_with?("Bearer ")
      render json: { error: "Missing token" }, status: :unauthorized
      return
    end

    token = auth_header.split(" ").last
    token_data = TokenService.verify_token(token)

    if token_data
      render json: {
        valid: true,
        expires_at: token_data[:expires_at],
        subscription_expires: token_data[:subscription_expires]
      }
    else
      render json: { valid: false }, status: :unauthorized
    end
  end

  # POST /api/v1/auth/refresh
  # Exchange a refresh token for a new access token (and rotate refresh token)
  def refresh
    refresh_token = params[:refresh_token]

    if refresh_token.blank?
      render json: { error: "Missing refresh token" }, status: :bad_request
      return
    end

    refreshed = RefreshTokenService.exchange(refresh_token)

    unless refreshed
      render json: { error: "Invalid or expired refresh token" }, status: :unauthorized
      return
    end

    user = refreshed[:user]
    token = TokenService.generate_token(user)

    unless token
      RefreshTokenService.revoke_for_user!(user)
      render json: { error: "Unable to issue access token" }, status: :unauthorized
      return
    end

    subscription = user.current_subscription

    render json: {
      token: token,
      refresh_token: refreshed[:refresh_token],
      expires_in: TokenService::ACCESS_TOKEN_EXPIRY.to_i,
      subscription_expires_at: subscription&.expires_at
    }, status: :ok
  end
end
