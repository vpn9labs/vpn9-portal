class AffiliatesController < ApplicationController
  allow_unauthenticated_access only: [ :index, :new, :create, :thank_you, :login, :authenticate, :logout ]
  layout "public"

  def index
    # Redirect based on authentication status
    if session[:affiliate_id] && Affiliate.exists?(id: session[:affiliate_id])
      redirect_to affiliates_dashboard_path
    else
      redirect_to login_affiliates_path
    end
  end

  def new
    @affiliate = Affiliate.new
  end

  def create
    @affiliate = Affiliate.new(affiliate_params)

    # Auto-generate code if not provided
    @affiliate.code ||= generate_unique_code

    # Set default values
    @affiliate.status = :pending
    @affiliate.commission_rate ||= 20.0 # Default 20% commission
    @affiliate.minimum_payout_amount ||= 100.0

    if @affiliate.save
      # Send welcome email
      AffiliateMailer.welcome(@affiliate).deliver_later

      # Set session to log them in
      session[:affiliate_id] = @affiliate.id

      redirect_to thank_you_affiliates_path
    else
      render :new, status: :unprocessable_content
    end
  end

  def thank_you
    @affiliate = Affiliate.find_by(id: session[:affiliate_id])
    redirect_to new_affiliate_path unless @affiliate
  end

  def login
    # Login page for existing affiliates
  end

  def authenticate
    affiliate = Affiliate.find_by(email: params[:email])

    if affiliate && affiliate.authenticate(params[:password])
      session[:affiliate_id] = affiliate.id
      redirect_to affiliates_dashboard_path
    else
      flash.now[:alert] = "Invalid email or password"
      render :login, status: :unprocessable_content
    end
  end

  def logout
    if session[:affiliate_id]
      session.delete(:affiliate_id)
      redirect_to login_affiliates_path, notice: "You have been logged out"
    else
      redirect_to login_affiliates_path
    end
  end

  private

  def affiliate_params
    params.require(:affiliate).permit(
      :name, :email, :password, :password_confirmation,
      :company_name, :website, :promotional_methods,
      :expected_referrals, :payout_currency, :payout_address,
      :tax_id, :address, :city, :state, :country, :postal_code,
      :phone, :terms_accepted
    )
  end

  def generate_unique_code
    loop do
      code = SecureRandom.alphanumeric(8).upcase
      break code unless Affiliate.exists?(code: code)
    end
  end
end
