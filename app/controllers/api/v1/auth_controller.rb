class Api::V1::AuthController < ActionController::API
  # POST /api/v1/auth/token
  # Get a token for VPN access - NO tracking, NO logging
  def token
    passphrase = params[:passphrase]

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

    # Return token with minimal information
    render json: {
      token: token,
      expires_in: TokenService::ACCESS_TOKEN_EXPIRY.to_i,
      subscription_expires_at: user.current_subscription.expires_at
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
end
