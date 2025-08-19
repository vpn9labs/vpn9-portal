class Admin::AffiliatesController < Admin::BaseController
  before_action :set_affiliate, only: [ :show, :edit, :update, :destroy, :toggle_status ]

  def index
    @affiliates = Affiliate.includes(:referrals, :commissions)
                           .order(created_at: :desc)
                           .page(params[:page])

    # Calculate aggregate stats
    @total_affiliates = Affiliate.count
    @active_affiliates = Affiliate.active.count
    @total_referrals = Referral.count
    @total_commissions = Commission.sum(:amount)
  end

  def show
    @recent_referrals = @affiliate.referrals.recent.limit(10)
    @recent_commissions = @affiliate.commissions.recent.limit(10)
    @recent_clicks = @affiliate.affiliate_clicks.recent.limit(20)

    # Performance metrics
    @metrics = {
      total_clicks: @affiliate.total_clicks,
      total_referrals: @affiliate.referrals.count,
      converted_referrals: @affiliate.referrals.converted.count,
      conversion_rate: @affiliate.conversion_rate,
      lifetime_earnings: @affiliate.lifetime_earnings,
      pending_balance: @affiliate.pending_balance,
      paid_out_total: @affiliate.paid_out_total,
      avg_commission: @affiliate.commissions.average(:amount) || 0
    }

    # Fraud indicators
    @fraud_indicators = check_fraud_indicators(@affiliate)
  end

  def new
    @affiliate = Affiliate.new
  end

  def create
    @affiliate = Affiliate.new(affiliate_params)
    @affiliate.code = generate_unique_code if @affiliate.code.blank?

    if @affiliate.save
      redirect_to admin_affiliate_path(@affiliate), notice: "Affiliate created successfully"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @affiliate.update(affiliate_params)
      redirect_to admin_affiliate_path(@affiliate), notice: "Affiliate updated successfully"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @affiliate.destroy
    redirect_to admin_affiliates_path, notice: "Affiliate deleted"
  end

  def toggle_status
    new_status = @affiliate.active? ? :suspended : :active
    @affiliate.update!(status: new_status)
    redirect_to admin_affiliate_path(@affiliate),
                notice: "Affiliate status changed to #{new_status}"
  end

  private

  def set_affiliate
    @affiliate = Affiliate.find(params[:id])
  end

  def affiliate_params
    params.require(:affiliate).permit(
      :name, :email, :code, :commission_rate, :status,
      :payout_address, :payout_currency, :cookie_duration_days,
      :notes, :minimum_payout_amount
    )
  end

  def generate_unique_code
    loop do
      code = SecureRandom.alphanumeric(8).upcase
      break code unless Affiliate.exists?(code: code)
    end
  end

  def check_fraud_indicators(affiliate)
    indicators = []

    # Check for suspicious click patterns
    recent_clicks = affiliate.affiliate_clicks.where(created_at: 24.hours.ago..)
    if recent_clicks.count > 100
      indicators << { type: :warning, message: "High click volume in last 24 hours: #{recent_clicks.count}" }
    end

    # Check for duplicate IP patterns
    ip_counts = recent_clicks.group(:ip_hash).count
    max_from_single_ip = ip_counts.values.max || 0
    if max_from_single_ip > 20
      indicators << { type: :warning, message: "Multiple clicks from same IP: #{max_from_single_ip}" }
    end

    # Check conversion rate anomalies
    if affiliate.conversion_rate > 50
      indicators << { type: :alert, message: "Unusually high conversion rate: #{affiliate.conversion_rate}%" }
    elsif affiliate.total_clicks > 100 && affiliate.conversion_rate < 0.1
      indicators << { type: :info, message: "Very low conversion rate: #{affiliate.conversion_rate}%" }
    end

    # Check for rapid signups
    recent_referrals = affiliate.referrals.where(created_at: 1.hour.ago..)
    if recent_referrals.count > 10
      indicators << { type: :alert, message: "Rapid signups in last hour: #{recent_referrals.count}" }
    end

    # Check commission patterns
    if affiliate.lifetime_earnings > 10000 && affiliate.commissions.cancelled.count > affiliate.commissions.paid.count
      indicators << { type: :warning, message: "High cancellation rate" }
    end

    indicators
  end
end
