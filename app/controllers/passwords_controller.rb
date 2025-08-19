class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  layout "public", only: %i[ new edit ]

  def new
  end

  def create
    # Handle recovery by email (if provided)
    if params[:email_address].present?
      if user = User.find_by(email_address: params[:email_address])
        PasswordsMailer.reset(user).deliver_later
      end
      redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
    # Handle recovery by recovery code
    elsif params[:recovery_code].present?
      user = User.find_by(recovery_code: params[:recovery_code])
      if user
        # Regenerate the passphrase
        new_passphrase = user.regenerate_passphrase!

        session[:show_new_passphrase] = {
          passphrase: new_passphrase
        }
        redirect_to new_session_path, notice: "Your passphrase has been reset. Please save your new passphrase."
      else
        redirect_to new_password_path, alert: "Invalid recovery code."
      end
    else
      redirect_to new_password_path, alert: "Please provide either an email address or recovery code."
    end
  end

  def edit
  end

  def update
    # This is for users who have email and want to set/change their additional password
    if @user.update(params.permit(:password, :password_confirmation))
      redirect_to new_session_path, notice: "Password has been updated."
    else
      redirect_to edit_password_path(params[:token]), alert: "Passwords did not match."
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end
