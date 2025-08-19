class AccountDeletionsController < ApplicationController
  def new
    @user = Current.user
  end

  def create
    user = Current.user

    # Verify passphrase for security
    passphrase = params[:passphrase]

    Rails.logger.info "Account deletion attempt for user #{user.id}, passphrase provided: #{passphrase.present?}"

    if user.verify_passphrase!(passphrase)
      reason = params[:reason].presence
      user.soft_delete!(reason: reason)

      # Log out the user by terminating their session
      terminate_session if respond_to?(:terminate_session)

      redirect_to root_path, notice: "Your account has been deleted. Your payment history has been preserved for legal requirements."
    else
      redirect_to new_account_deletion_path, alert: "Invalid passphrase. Please try again."
    end
  rescue => e
    Rails.logger.error "Account deletion failed: #{e.message}"
    redirect_to new_account_deletion_path, alert: "Unable to delete account. Please contact support."
  end
end
