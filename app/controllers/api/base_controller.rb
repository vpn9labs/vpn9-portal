class Api::BaseController < ActionController::API
  before_action :authenticate!

  private

  def authenticate!
    token = extract_token_from_header

    unless token
      render json: { error: "Missing authentication token" }, status: :unauthorized
      return
    end

    @current_user = TokenService.authenticate_token(token)

    unless @current_user
      render json: { error: "Invalid or expired token" }, status: :unauthorized
      return
    end

    # Verify subscription is still active
    unless @current_user.has_active_subscription?
      render json: {
        error: "No active subscription",
        subscription_required: true
      }, status: :payment_required
      nil
    end
  end

  def current_user
    @current_user
  end

  def extract_token_from_header
    auth_header = request.headers["Authorization"]
    return nil unless auth_header.present?

    auth_header.split(" ").last if auth_header.start_with?("Bearer ")
  end
end
