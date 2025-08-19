class Affiliates::DashboardController < Affiliates::BaseController
  def index
    @stats = {
      total_clicks: @current_affiliate.affiliate_clicks.count,
      unique_visitors: @current_affiliate.affiliate_clicks.distinct.count(:ip_hash),
      total_referrals: @current_affiliate.referrals.count,
      conversions: @current_affiliate.referrals.converted.count,
      pending_earnings: @current_affiliate.pending_balance,
      lifetime_earnings: @current_affiliate.lifetime_earnings,
      paid_out: @current_affiliate.paid_out_total
    }

    @recent_clicks = @current_affiliate.affiliate_clicks.recent.limit(10)
    @recent_referrals = @current_affiliate.referrals.recent.limit(10)
    @recent_commissions = @current_affiliate.commissions.recent.limit(10)

    # Generate referral links
    @referral_links = {
      homepage: root_url(ref: @current_affiliate.code),
      signup: signup_url(ref: @current_affiliate.code),
      plans: plans_url(ref: @current_affiliate.code)
    }

    # Performance chart data
    @chart_data = generate_chart_data
  end

  private

  def generate_chart_data
    last_30_days = (0..29).map do |days_ago|
      date = days_ago.days.ago.to_date
      day_range = date.beginning_of_day..date.end_of_day

      {
        date: date.strftime("%b %d"),
        clicks: @current_affiliate.affiliate_clicks.where(created_at: day_range).count,
        signups: @current_affiliate.referrals.where(created_at: day_range).count,
        conversions: @current_affiliate.referrals.converted.where(converted_at: day_range).count
      }
    end.reverse
  end
end
