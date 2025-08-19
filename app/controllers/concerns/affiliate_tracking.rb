module AffiliateTracking
  extend ActiveSupport::Concern

  included do
    before_action :track_affiliate_click
    helper_method :affiliate_tracked?
  end

  private

  def track_affiliate_click
    # Check for affiliate code in params
    if params[:ref].present?
      handle_affiliate_referral(params[:ref])
    elsif params[:affiliate].present?
      handle_affiliate_referral(params[:affiliate])
    elsif params[:r].present?
      handle_affiliate_referral(params[:r])
    end

    # Store landing page if this is the first visit with affiliate code
    if cookies.signed[:affiliate_code].present? && session[:landing_page].blank?
      session[:landing_page] = request.fullpath
    end
  end

  def handle_affiliate_referral(code)
    # Clean and normalize the code
    code = code.to_s.strip.upcase
    return if code.blank?

    # Find active affiliate
    affiliate = Affiliate.active.find_by(code: code)

    if affiliate
      # Set cookie for tracking (signed for security)
      cookies.signed[:affiliate_code] = {
        value: affiliate.code,
        expires: affiliate.cookie_duration_days.days.from_now,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax
      }

      # Store when the click happened
      cookies.signed[:affiliate_clicked_at] = {
        value: Time.current.to_i,
        expires: affiliate.cookie_duration_days.days.from_now,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax
      }

      # Track click (privacy-conscious)
      begin
        AffiliateClick.track_click(affiliate, request, request.fullpath)
      rescue => e
        Rails.logger.error "Failed to track affiliate click: #{e.message}"
      end

      # Log for monitoring
      Rails.logger.info "Affiliate tracked: #{affiliate.code} from IP: #{hash_ip(request.remote_ip)}"
    else
      Rails.logger.warn "Invalid affiliate code attempted: #{code}"
    end
  end

  def affiliate_tracked?
    cookies.signed[:affiliate_code].present?
  end

  def current_affiliate_code
    cookies.signed[:affiliate_code]
  end

  def track_referral(user)
    return unless user && cookies.signed[:affiliate_code].present?

    affiliate = Affiliate.active.find_by(code: cookies.signed[:affiliate_code])
    return unless affiliate

    # Check if referral already exists (shouldn't happen but be safe)
    return if user.referral.present?

    begin
      # Create referral record
      referral = Referral.create!(
        affiliate: affiliate,
        user: user,
        referral_code: affiliate.code,
        landing_page: session[:landing_page],
        ip_hash: hash_ip(request.remote_ip),
        clicked_at: Time.at(cookies.signed[:affiliate_clicked_at].to_i)
      )

      # Clear affiliate cookies after successful tracking
      clear_affiliate_cookies

      Rails.logger.info "Referral created: User ##{user.id} referred by #{affiliate.code}"

      referral
    rescue => e
      Rails.logger.error "Failed to create referral: #{e.message}"
      nil
    end
  end

  def clear_affiliate_cookies
    cookies.delete(:affiliate_code)
    cookies.delete(:affiliate_clicked_at)
    session.delete(:landing_page)
  end

  def hash_ip(ip)
    return nil if ip.blank?
    Digest::SHA256.hexdigest("#{ip}#{Rails.application.secret_key_base}")
  end

  def hash_string(str)
    return nil if str.blank?
    Digest::SHA256.hexdigest("#{str}#{Rails.application.secret_key_base}")
  end
end
