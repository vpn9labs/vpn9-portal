class AffiliateClick < ApplicationRecord
  belongs_to :affiliate

  validates :ip_hash, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :converted, -> { where(converted: true) }
  scope :unconverted, -> { where(converted: false) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :this_week, -> { where("created_at >= ?", 1.week.ago) }
  scope :this_month, -> { where("created_at >= ?", 1.month.ago) }

  # Privacy-conscious: we don't store actual IPs or user agents
  def self.track_click(affiliate, request, landing_page = nil)
    create!(
      affiliate: affiliate,
      ip_hash: hash_ip(request.remote_ip),
      user_agent_hash: hash_string(request.user_agent),
      landing_page: landing_page || request.fullpath,
      referrer: request.referrer
    )
  end

  def self.hash_ip(ip)
    return nil if ip.blank?
    Digest::SHA256.hexdigest("#{ip}#{Rails.application.secret_key_base}")
  end

  def self.hash_string(str)
    return nil if str.blank?
    Digest::SHA256.hexdigest("#{str}#{Rails.application.secret_key_base}")
  end
end
