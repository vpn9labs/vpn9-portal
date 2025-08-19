class SignupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create, with: -> { redirect_to signup_url, alert: t(".try_again_later") } unless Rails.env.test?
  layout "public"

  def new
    @user = User.new
  end

  def create
    # Get params first
    account_type = params.dig(:user, :account_type)
    permitted = user_params

    # Handle different account types
    if account_type == "email"
      # Email account requires email address
      if permitted[:email_address].blank?
        @user = User.new
        @user.errors.add(:email_address, "is required for email accounts")
        render :new, status: :unprocessable_content
        return
      end
      # Remove any password fields for email accounts (only passphrase authentication)
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    elsif account_type == "anonymous"
      # Anonymous account - ensure no email
      permitted.delete(:email_address)
      permitted.delete(:password)
      permitted.delete(:password_confirmation)
    end

    @user = User.new(permitted)

    if @user.save
      # Track affiliate referral if present
      track_referral(@user)

      start_new_session_for @user

      if @user.send(:issued_passphrase).present?
        # Store passphrase and recovery code in session to display once
        session[:show_credentials] = {
          passphrase: @user.send(:issued_passphrase),
          recovery_code: @user.recovery_code,
          account_type: account_type
        }
        redirect_to root_url, notice: t(".success_with_passphrase")
      else
        redirect_to root_url, notice: t(".success")
      end
    else
      render :new, status: :unprocessable_content
    end
  rescue ActionController::ParameterMissing => e
    # Handle missing user parameter
    head :bad_request
  rescue ActiveRecord::RecordNotUnique => e
    @user.errors.add(:email_address, "has already been taken")
    render :new, status: :unprocessable_content
  end

  private

  def user_params
    params.require(:user)
      .permit(:email_address, :password, :password_confirmation, :account_type)
      .tap do |p|
        p.delete(:email_address) if p[:email_address].blank?
        p.delete(:account_type) # Don't save account_type to database
      end
  end
end
