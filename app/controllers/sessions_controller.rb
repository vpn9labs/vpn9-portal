class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: t("sessions.rate_limit_exceeded") } unless Rails.env.test?
  layout "public", only: %i[ new ]

  def new
  end

  def create
    permitted_params = params.permit(:passphrase, :email_address)

    # Authenticate using passphrase (with optional email)
    user = User.authenticate_by_passphrase(
      permitted_params[:passphrase],
      email: permitted_params[:email_address]
    )

    if user
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t(".invalid_passphrase")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end
end
