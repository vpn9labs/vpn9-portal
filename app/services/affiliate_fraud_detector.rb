#
# AffiliateFraudDetector evaluates affiliate activity for fraud risk.
#
# It inspects click/sign‑up velocity, conversion rates, IP concentration,
# timing/pattern anomalies, and commission reversal history to compute a
# bounded risk score and flags with recommendations.
#
# Usage
#   detector = AffiliateFraudDetector.new(affiliate, 24.hours)
#   detector.check_all #=> { risk_score:, flags:, recommendations:, metrics: }
#   detector.suspicious?
#   detector.high_risk?
#
class AffiliateFraudDetector
  # @return [Affiliate] affiliate being evaluated
  # @return [ActiveSupport::Duration] lookback window for certain metrics
  attr_reader :affiliate, :period

  # Thresholds controlling anomaly detection.
  # @return [Hash]
  THRESHOLDS = {
    max_clicks_per_hour: 50,
    max_clicks_per_day: 500,
    max_signups_per_hour: 10,
    max_signups_per_day: 50,
    min_conversion_rate: 0.1,
    max_conversion_rate: 30.0,
    max_same_ip_clicks: 20,
    suspicious_user_agent_patterns: [
      /bot/i,
      /crawler/i,
      /spider/i,
      /scraper/i
    ]
  }.freeze

  # @param affiliate [Affiliate]
  # @param period [ActiveSupport::Duration] lookback period for selected metrics (default: 24 hours)
  def initialize(affiliate, period = 24.hours)
    @affiliate = affiliate
    @period = period
  end

  # Run a full evaluation and return score, flags, recommendations, and raw metrics.
  # @return [Hash] keys: :risk_score (Integer 0..100), :flags (Array<Hash>), :recommendations (Array<String>), :metrics (Hash)
  def check_all
    {
      risk_score: calculate_risk_score,
      flags: collect_flags,
      recommendations: generate_recommendations,
      metrics: collect_metrics
    }
  end

  # Whether risk score exceeds the suspicious threshold (> 50).
  # @return [Boolean]
  def suspicious?
    calculate_risk_score > 50
  end

  # Whether risk score exceeds the high‑risk threshold (> 75).
  # @return [Boolean]
  def high_risk?
    calculate_risk_score > 75
  end

  private

  # Compute bounded risk score (0..100) across multiple signals.
  # @api private
  def calculate_risk_score
    score = 0

    # Check click velocity
    clicks_last_hour = recent_clicks(1.hour).count
    clicks_last_day = recent_clicks(24.hours).count

    score += 20 if clicks_last_hour > THRESHOLDS[:max_clicks_per_hour]
    score += 15 if clicks_last_day > THRESHOLDS[:max_clicks_per_day]

    # Check signup velocity
    signups_last_hour = recent_referrals(1.hour).count
    signups_last_day = recent_referrals(24.hours).count

    score += 25 if signups_last_hour > THRESHOLDS[:max_signups_per_hour]
    score += 20 if signups_last_day > THRESHOLDS[:max_signups_per_day]

    # Check conversion rate anomalies
    conversion_rate = affiliate.conversion_rate
    if affiliate.total_clicks > 100
      score += 30 if conversion_rate > THRESHOLDS[:max_conversion_rate]
      score += 10 if conversion_rate < THRESHOLDS[:min_conversion_rate]
    end

    # Check IP concentration
    ip_concentration = calculate_ip_concentration
    score += 20 if ip_concentration > 0.5 # More than 50% from same IP

    # Check for suspicious patterns
    score += 15 if has_suspicious_click_patterns?
    score += 10 if has_suspicious_timing_patterns?

    # Check commission reversals
    if affiliate.commissions.count > 10
      reversal_rate = affiliate.commissions.cancelled.count.to_f / affiliate.commissions.count
      score += 15 if reversal_rate > 0.3
    end

    [ score, 100 ].min # Cap at 100
  end

  # Collect human‑readable flags for detected anomalies with severities.
  # @return [Array<Hash>] each with :type, :severity, :message
  def collect_flags
    flags = []

    # Velocity checks
    clicks_last_hour = recent_clicks(1.hour).count
    if clicks_last_hour > THRESHOLDS[:max_clicks_per_hour]
      flags << {
        type: :high_click_velocity,
        severity: :high,
        message: "#{clicks_last_hour} clicks in last hour (threshold: #{THRESHOLDS[:max_clicks_per_hour]})"
      }
    end

    signups_last_hour = recent_referrals(1.hour).count
    if signups_last_hour > THRESHOLDS[:max_signups_per_hour]
      flags << {
        type: :high_signup_velocity,
        severity: :high,
        message: "#{signups_last_hour} signups in last hour (threshold: #{THRESHOLDS[:max_signups_per_hour]})"
      }
    end

    # Conversion rate checks
    if affiliate.total_clicks > 100
      conversion_rate = affiliate.conversion_rate
      if conversion_rate > THRESHOLDS[:max_conversion_rate]
        flags << {
          type: :abnormal_conversion_rate,
          severity: :high,
          message: "Conversion rate of #{conversion_rate}% is unusually high"
        }
      elsif conversion_rate < THRESHOLDS[:min_conversion_rate]
        flags << {
          type: :low_conversion_rate,
          severity: :medium,
          message: "Conversion rate of #{conversion_rate}% is unusually low"
        }
      end
    end

    # IP concentration
    ip_concentration = calculate_ip_concentration
    if ip_concentration > 0.5
      flags << {
        type: :ip_concentration,
        severity: :high,
        message: "#{(ip_concentration * 100).round}% of clicks from same IP"
      }
    end

    # Pattern checks
    if has_suspicious_click_patterns?
      flags << {
        type: :suspicious_patterns,
        severity: :medium,
        message: "Detected suspicious click patterns"
      }
    end

    if has_suspicious_timing_patterns?
      flags << {
        type: :suspicious_timing,
        severity: :medium,
        message: "Detected suspicious timing patterns"
      }
    end

    # Payment history
    if affiliate.commissions.count > 10
      reversal_rate = affiliate.commissions.cancelled.count.to_f / affiliate.commissions.count
      if reversal_rate > 0.3
        flags << {
          type: :high_reversal_rate,
          severity: :medium,
          message: "#{(reversal_rate * 100).round}% commission reversal rate"
        }
      end
    end

    flags
  end

  # Generate action recommendations based on score and flags.
  # @return [Array<String>]
  def generate_recommendations
    recommendations = []
    risk_score = calculate_risk_score

    if risk_score > 75
      recommendations << "Immediately suspend affiliate pending investigation"
      recommendations << "Review all recent referrals for validity"
      recommendations << "Consider reversing recent commissions"
    elsif risk_score > 50
      recommendations << "Monitor affiliate activity closely"
      recommendations << "Consider manual approval for commissions"
      recommendations << "Review click and signup patterns"
    elsif risk_score > 25
      recommendations << "Keep affiliate under observation"
      recommendations << "Verify payout details before processing"
    end

    # Specific recommendations based on flags
    flags = collect_flags

    if flags.any? { |f| f[:type] == :ip_concentration }
      recommendations << "Investigate traffic sources for IP diversity"
    end

    if flags.any? { |f| f[:type] == :abnormal_conversion_rate }
      recommendations << "Audit conversion tracking for accuracy"
    end

    recommendations
  end

  # Gather raw metrics used by the detector.
  # @return [Hash]
  def collect_metrics
    {
      clicks_last_hour: recent_clicks(1.hour).count,
      clicks_last_24h: recent_clicks(24.hours).count,
      signups_last_hour: recent_referrals(1.hour).count,
      signups_last_24h: recent_referrals(24.hours).count,
      unique_ips_last_24h: recent_clicks(24.hours).distinct.count(:ip_hash),
      conversion_rate: affiliate.conversion_rate,
      avg_time_to_conversion: calculate_avg_time_to_conversion,
      commission_reversal_rate: calculate_reversal_rate
    }
  end

  # Recent clicks scoped to a time duration.
  # @api private
  def recent_clicks(duration)
    affiliate.affiliate_clicks.where(created_at: duration.ago..)
  end

  # Recent referrals scoped to a time duration.
  # @api private
  def recent_referrals(duration)
    affiliate.referrals.where(created_at: duration.ago..)
  end

  # Fraction of clicks from the single most common IP over @period.
  # @return [Float] 0.0..1.0
  def calculate_ip_concentration
    clicks = recent_clicks(@period)
    return 0 if clicks.empty?

    ip_counts = clicks.group(:ip_hash).count
    max_from_single_ip = ip_counts.values.max || 0

    max_from_single_ip.to_f / clicks.count
  end

  # Detect repeated, bot‑like click intervals in the last hour.
  # @return [Boolean]
  def has_suspicious_click_patterns?
    # Check for rapid-fire clicking
    clicks = recent_clicks(1.hour).order(:created_at)
    return false if clicks.size < 10

    # Check intervals between clicks
    intervals = []
    clicks.each_cons(2) do |click1, click2|
      intervals << (click2.created_at - click1.created_at)
    end

    # Suspicious if many clicks have exact same interval (bot-like behavior)
    interval_counts = intervals.group_by { |i| i.round }.transform_values(&:count)
    max_same_interval = interval_counts.values.max || 0

    max_same_interval > intervals.size * 0.3 # More than 30% with same interval
  end

  # Detect narrow timing windows of activity over the last 7 days.
  # @return [Boolean]
  def has_suspicious_timing_patterns?
    # Check if all activity happens in specific time windows (bot-like)
    clicks = recent_clicks(7.days)
    return false if clicks.size < 50

    # Group by hour of day
    hour_distribution = clicks.group_by { |c| c.created_at.hour }
                               .transform_values(&:count)

    # Suspicious if all activity in narrow time window
    active_hours = hour_distribution.keys.size
    active_hours < 4 # Activity only in less than 4 hours of the day
  end

  def calculate_avg_time_to_conversion
    converted = affiliate.referrals.converted.includes(:commissions)
    return 0 if converted.empty?

    times = converted.map do |referral|
      first_commission = referral.commissions.minimum(:created_at)
      next unless first_commission

      (first_commission - referral.created_at) / 1.hour
    end.compact

    return 0 if times.empty?
    times.sum / times.size
  end

  # Percentage of cancelled commissions among all commissions.
  # @return [Float] percentage 0..100 with 2 decimals
  def calculate_reversal_rate
    total = affiliate.commissions.count
    return 0 if total.zero?

    cancelled = affiliate.commissions.cancelled.count
    (cancelled.to_f / total * 100).round(2)
  end
end
