class Affiliates::ProfilesController < Affiliates::BaseController
  before_action :set_affiliate

  def show
    # Display profile information
  end

  def edit
    # Edit profile form
  end

  def update
    if @affiliate.update(profile_params)
      redirect_to affiliates_profile_path, notice: "Profile updated successfully"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def update_password
    if @affiliate.authenticate(params[:current_password])
      if @affiliate.update(password_params)
        redirect_to affiliates_profile_path, notice: "Password updated successfully"
      else
        redirect_to edit_affiliates_profile_path, alert: "Password update failed: #{@affiliate.errors.full_messages.join(', ')}"
      end
    else
      redirect_to edit_affiliates_profile_path, alert: "Current password is incorrect"
    end
  end

  private

  def set_affiliate
    @affiliate = @current_affiliate
  end

  def profile_params
    params.require(:affiliate).permit(
      :name,
      :email,
      :company_name,
      :website,
      :phone,
      :address,
      :city,
      :state,
      :country,
      :postal_code,
      :tax_id,
      :promotional_methods,
      :expected_referrals
    )
  end

  def password_params
    params.require(:affiliate).permit(:password, :password_confirmation)
  end
end
