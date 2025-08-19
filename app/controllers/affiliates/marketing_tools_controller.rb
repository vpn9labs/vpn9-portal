class Affiliates::MarketingToolsController < Affiliates::BaseController
  def index
    @referral_links = generate_referral_links
    @banners = available_banners
    @email_templates = available_email_templates
  end

  def link_generator
    @base_url = params[:url] || root_url
    @generated_link = add_referral_code(@base_url)
  end

  def banners
    @banners = available_banners
  end

  def email_templates
    @templates = available_email_templates
  end

  private

  def generate_referral_links
    {
      homepage: root_url(ref: @current_affiliate.code),
      signup: signup_url(ref: @current_affiliate.code),
      plans: plans_url(ref: @current_affiliate.code),
      features: root_url(ref: @current_affiliate.code, anchor: "features"),
      pricing: plans_url(ref: @current_affiliate.code)
    }
  end

  def add_referral_code(url)
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query || "")
    params << [ "ref", @current_affiliate.code ]
    uri.query = URI.encode_www_form(params)
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  def available_banners
    [
      { size: "728x90", name: "Leaderboard", image: "banner-728x90.png" },
      { size: "300x250", name: "Medium Rectangle", image: "banner-300x250.png" },
      { size: "320x50", name: "Mobile Banner", image: "banner-320x50.png" },
      { size: "160x600", name: "Wide Skyscraper", image: "banner-160x600.png" }
    ]
  end

  def available_email_templates
    [
      {
        name: "Introduction Email",
        subject: "Secure Your Online Privacy with VPN9",
        preview: "Introduce your audience to VPN9's privacy features..."
      },
      {
        name: "Special Offer Email",
        subject: "Exclusive VPN9 Discount for You",
        preview: "Share exclusive discounts with your subscribers..."
      },
      {
        name: "Security Alert Email",
        subject: "Protect Yourself from Online Threats",
        preview: "Educate your audience about online security..."
      }
    ]
  end
end
