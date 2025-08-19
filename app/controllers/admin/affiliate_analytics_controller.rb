class Admin::AffiliateAnalyticsController < Admin::BaseController
  def index
    @date_range = parse_date_range

    # Overall metrics
    @overall_metrics = {
      total_affiliates: Affiliate.count,
      active_affiliates: Affiliate.active.count,
      total_clicks: AffiliateClick.where(created_at: @date_range).count,
      total_referrals: Referral.where(created_at: @date_range).count,
      converted_referrals: Referral.converted.where(created_at: @date_range).count,
      total_revenue: Payment.successful.where(created_at: @date_range).sum(:amount),
      total_commissions: Commission.where(created_at: @date_range).sum(:amount),
      avg_conversion_rate: calculate_avg_conversion_rate(@date_range)
    }

    # Top performers
    @top_affiliates = Affiliate.active
                               .joins(:commissions)
                               .where(commissions: { created_at: @date_range })
                               .group("affiliates.id")
                               .order(Arel.sql("SUM(commissions.amount) DESC"))
                               .limit(10)
                               .select("affiliates.*, SUM(commissions.amount) as total_earnings")

    # Performance by time
    @daily_stats = calculate_daily_stats(@date_range)

    # Conversion funnel
    @funnel_stats = calculate_funnel_stats(@date_range)

    # Geographic distribution (if tracking)
    @geo_stats = calculate_geo_stats(@date_range)

    # Traffic sources
    @traffic_sources = calculate_traffic_sources(@date_range)

    # Daily performance for chart
    @daily_performance = calculate_daily_performance(@date_range)

    # Recent conversions
    @recent_conversions = Referral.converted
                                  .includes(:affiliate, :user)
                                  .where(created_at: @date_range)
                                  .order(converted_at: :desc)
                                  .limit(20)

    # Top traffic sources (referrers)
    @top_sources = AffiliateClick.where(created_at: @date_range)
                                 .where.not(referrer: [ nil, "" ])
                                 .group(:referrer)
                                 .order(Arel.sql("COUNT(*) DESC"))
                                 .limit(10)
                                 .count
  end

  def affiliate
    @affiliate = Affiliate.find(params[:id])
    @date_range = parse_date_range

    # Affiliate specific metrics
    clicks = @affiliate.affiliate_clicks.where(created_at: @date_range).count
    signups = @affiliate.referrals.where(created_at: @date_range).count
    conversions = @affiliate.referrals.converted.where(created_at: @date_range).count
    earnings = @affiliate.commissions.where(created_at: @date_range).sum(:amount)

    @stats = {
      clicks: clicks,
      unique_visitors: @affiliate.affiliate_clicks.where(created_at: @date_range).distinct.count(:ip_hash),
      signups: signups,
      conversions: conversions,
      earnings: earnings,
      conversion_rate: clicks > 0 ? (conversions.to_f / clicks * 100) : 0,
      signup_rate: clicks > 0 ? (signups.to_f / clicks * 100) : 0,
      avg_commission: conversions > 0 ? (earnings / conversions) : 0
    }

    # Performance over time
    @daily_performance = calculate_affiliate_daily_performance(@affiliate, @date_range)

    # Top converting pages
    @top_pages = @affiliate.affiliate_clicks
                           .where(created_at: @date_range)
                           .group(:landing_page)
                           .order(Arel.sql("COUNT(*) DESC"))
                           .limit(10)
                           .count

    # Fraud detection
    detector = AffiliateFraudDetector.new(@affiliate)
    @fraud_analysis = detector.check_all

    # Recent activity
    @recent_clicks = @affiliate.affiliate_clicks.recent.limit(20)
    @recent_referrals = @affiliate.referrals.recent.limit(10)
    @recent_commissions = @affiliate.commissions.recent.limit(10)
  end

  def export
    @date_range = parse_date_range

    respond_to do |format|
      format.html { redirect_to admin_analytics_path, alert: "Please specify a format (CSV, JSON, or PDF)" }
      format.csv { send_data generate_analytics_csv(@date_range), filename: "affiliate_analytics_#{Date.current}.csv" }
      format.json { render json: generate_analytics_json(@date_range) }
      format.pdf { render pdf: generate_analytics_pdf(@date_range) }
    end
  end

  private

  def parse_date_range
    if params[:start_date].present? && params[:end_date].present?
      begin
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
      rescue Date::Error, ArgumentError
        # Invalid date format, use default
        start_date = 30.days.ago.to_date
        end_date = Date.current
      end
    elsif params[:period].present?
      case params[:period]
      when "today"
        start_date = Date.current
        end_date = Date.current
      when "week"
        start_date = 1.week.ago.to_date
        end_date = Date.current
      when "month"
        start_date = 1.month.ago.to_date
        end_date = Date.current
      when "quarter"
        start_date = 3.months.ago.to_date
        end_date = Date.current
      when "year"
        start_date = 1.year.ago.to_date
        end_date = Date.current
      else
        start_date = 30.days.ago.to_date
        end_date = Date.current
      end
    else
      start_date = 30.days.ago.to_date
      end_date = Date.current
    end

    start_date.beginning_of_day..end_date.end_of_day
  end

  def calculate_avg_conversion_rate(date_range)
    total_clicks = AffiliateClick.where(created_at: date_range).count
    return 0 if total_clicks.zero?

    converted = Referral.converted.where(created_at: date_range).count
    (converted.to_f / total_clicks * 100).round(2)
  end

  def calculate_signup_rate(affiliate, date_range)
    clicks = affiliate.affiliate_clicks.where(created_at: date_range).count
    return 0 if clicks.zero?

    signups = affiliate.referrals.where(created_at: date_range).count
    (signups.to_f / clicks * 100).round(2)
  end

  def calculate_affiliate_conversion_rate(affiliate, date_range)
    clicks = affiliate.affiliate_clicks.where(created_at: date_range).count
    return 0 if clicks.zero?

    converted = affiliate.referrals.converted.where(created_at: date_range).count
    (converted.to_f / clicks * 100).round(2)
  end

  def calculate_avg_order_value(affiliate, date_range)
    commissions = affiliate.commissions.where(created_at: date_range)
    return 0 if commissions.empty?

    total_amount = commissions.joins(:payment).sum("payments.amount")
    total_amount / commissions.count
  end

  def calculate_daily_performance(date_range)
    calculate_daily_stats(date_range)
  end

  def calculate_daily_stats(date_range)
    start_date = date_range.first.to_date
    end_date = date_range.last.to_date

    (start_date..end_date).map do |date|
      day_range = date.beginning_of_day..date.end_of_day

      {
        date: date,
        clicks: AffiliateClick.where(created_at: day_range).count,
        referrals: Referral.where(created_at: day_range).count,
        conversions: Referral.converted.where(created_at: day_range).count,
        revenue: Payment.successful.where(created_at: day_range).sum(:amount),
        commissions: Commission.where(created_at: day_range).sum(:amount)
      }
    end
  end

  def calculate_affiliate_daily_performance(affiliate, date_range)
    start_date = date_range.first.to_date
    end_date = date_range.last.to_date

    (start_date..end_date).map do |date|
      day_range = date.beginning_of_day..date.end_of_day

      {
        date: date,
        clicks: affiliate.affiliate_clicks.where(created_at: day_range).count,
        referrals: affiliate.referrals.where(created_at: day_range).count,
        conversions: affiliate.referrals.converted.where(created_at: day_range).count,
        earnings: affiliate.commissions.where(created_at: day_range).sum(:amount)
      }
    end
  end

  def calculate_funnel_stats(date_range)
    # Calculate revenue from payments that have commissions
    revenue = Commission.joins(:referral, :payment)
                       .where(referrals: { created_at: date_range })
                       .where(payments: { status: [ :paid, :overpaid ] })
                       .sum("payments.amount")

    {
      clicks: AffiliateClick.where(created_at: date_range).count,
      unique_visitors: AffiliateClick.where(created_at: date_range).distinct.count(:ip_hash),
      signups: Referral.where(created_at: date_range).count,
      conversions: Referral.converted.where(created_at: date_range).count,
      revenue: revenue
    }
  end

  def calculate_geo_stats(date_range)
    # This would require GeoIP lookup on IP hashes
    # Placeholder for now
    {
      countries: {},
      regions: {}
    }
  end

  def calculate_traffic_sources(date_range)
    AffiliateClick.where(created_at: date_range)
                  .group(:landing_page)
                  .order(Arel.sql("COUNT(*) DESC"))
                  .limit(20)
                  .count
  end

  def generate_analytics_csv(date_range)
    require "csv"

    CSV.generate(headers: true) do |csv|
      csv << [ "Affiliate Analytics Report", "Generated: #{Date.current}" ]
      csv << [ "Date Range", date_range.first.to_date, date_range.last.to_date ]
      csv << []

      csv << [ "Affiliate", "Code", "Clicks", "Referrals", "Conversions", "Conv Rate", "Earnings", "Status" ]

      Affiliate.includes(:affiliate_clicks, :referrals, :commissions).find_each do |affiliate|
        clicks = affiliate.affiliate_clicks.where(created_at: date_range).count
        referrals = affiliate.referrals.where(created_at: date_range).count
        conversions = affiliate.referrals.converted.where(created_at: date_range).count
        conv_rate = clicks > 0 ? (conversions.to_f / clicks * 100).round(2) : 0
        earnings = affiliate.commissions.where(created_at: date_range).sum(:amount)

        csv << [
          affiliate.name || "N/A",
          affiliate.code,
          clicks,
          referrals,
          conversions,
          "#{conv_rate}%",
          "$#{earnings}",
          affiliate.status
        ]
      end
    end
  end

  def generate_analytics_json(date_range)
    {
      report_date: Date.current,
      date_range: {
        start: date_range.first,
        end: date_range.last
      },
      overall_metrics: @overall_metrics,
      top_performers: @top_affiliates.map do |affiliate|
        {
          id: affiliate.id,
          name: affiliate.name,
          code: affiliate.code,
          earnings: affiliate.total_earnings
        }
      end,
      daily_stats: @daily_stats,
      funnel: @funnel_stats
    }
  end

  def generate_analytics_pdf(date_range)
    # This would use a PDF generation library like Prawn
    # Placeholder for now
    "PDF generation not implemented"
  end
end
