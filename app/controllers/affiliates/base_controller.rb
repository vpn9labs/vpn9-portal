class Affiliates::BaseController < ApplicationController
  allow_unauthenticated_access
  before_action :authenticate_affiliate
  layout "affiliate"

  private

  def authenticate_affiliate
    @current_affiliate = Affiliate.find_by(id: session[:affiliate_id])

    unless @current_affiliate && @current_affiliate.active?
      session.delete(:affiliate_id)
      redirect_to login_affiliates_path, alert: "Please log in to continue"
    end
  end
end
