class AffiliateMailer < ApplicationMailer
  def welcome(affiliate)
    @affiliate = affiliate
    mail(
      to: affiliate.email,
      subject: "Welcome to the VPN9 Affiliate Program!"
    )
  end

  def approval(affiliate)
    @affiliate = affiliate
    mail(
      to: affiliate.email,
      subject: "Your VPN9 Affiliate Account Has Been Approved!"
    )
  end

  def rejection(affiliate)
    @affiliate = affiliate
    mail(
      to: affiliate.email,
      subject: "VPN9 Affiliate Application Update"
    )
  end

  def payout_processed(affiliate, payout)
    @affiliate = affiliate
    @payout = payout
    mail(
      to: affiliate.email,
      subject: "Your VPN9 Affiliate Payout Has Been Processed"
    )
  end
end
