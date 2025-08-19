class Affiliates::ReferralsController < Affiliates::BaseController
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  def index
    @referrals = @current_affiliate.referrals
                                   .includes(:user)
                                   .order(created_at: :desc)
                                   .page(params[:page])

    @stats = {
      total: @current_affiliate.referrals.count,
      pending: @current_affiliate.referrals.pending.count,
      converted: @current_affiliate.referrals.converted.count,
      rejected: @current_affiliate.referrals.rejected.count
    }
  end

  def show
    @referral = @current_affiliate.referrals.find(params[:id])
    @commission = @referral.commissions.first if @referral.converted?
    @clicks = @current_affiliate.affiliate_clicks
                                .where(ip_hash: @referral.ip_hash)
                                .where("created_at <= ?", @referral.created_at)
                                .order(created_at: :desc)
  end

  private

  def record_not_found
    render plain: "404 Not Found", status: :not_found
  end
end
