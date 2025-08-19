class Affiliate < ApplicationRecord
  has_secure_password validations: false

  has_many :referrals, dependent: :destroy
  has_many :commissions, dependent: :destroy
  has_many :affiliate_clicks, dependent: :destroy
  has_many :referred_users, through: :referrals, source: :user
  has_many :payouts, dependent: :destroy

  enum :status, { active: 0, suspended: 1, terminated: 2, pending: 3 }

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :commission_rate, numericality: { in: 0..100 }
  validates :payout_address, presence: true, if: :payout_currency?
  validates :payout_currency, inclusion: { in: %w[btc eth usdt ltc xmr bank manual] }, allow_blank: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :password, presence: true, on: :create, if: :password_required?
  validates :password, confirmation: true, if: :password_required?
  validates :password_confirmation, presence: true, if: :password_required?
  validates :terms_accepted, acceptance: { message: "must be accepted" }, on: :create, if: :terms_required?
  validates :cookie_duration_days, numericality: { greater_than: 0, less_than_or_equal_to: 365 }
  validates :attribution_window_days, numericality: { greater_than: 0, less_than_or_equal_to: 365 }

  before_validation :generate_code, on: :create
  before_validation :normalize_code

  scope :with_stats, -> {
    left_joins(:referrals, :commissions)
      .select("affiliates.*",
              "COUNT(DISTINCT referrals.id) as total_referrals",
              "COUNT(DISTINCT CASE WHEN referrals.status = 1 THEN referrals.id END) as converted_referrals",
              "COALESCE(SUM(DISTINCT commissions.amount), 0) as total_commissions")
      .group("affiliates.id")
  }

  def total_pending_commission
    commissions.pending.sum(:amount)
  end

  def total_approved_commission
    commissions.approved.sum(:amount)
  end

  def total_clicks
    affiliate_clicks.count
  end

  def conversion_rate
    return 0.0 if total_clicks.zero?
    (referrals.converted.count.to_f / total_clicks * 100).round(2)
  end

  def referral_link(base_url = nil)
    base_url ||= ENV["APP_URL"] || "https://vpn9.com"
    "#{base_url}?ref=#{code}"
  end

  def eligible_for_payout?(minimum_amount = 50.0)
    total_approved_commission >= minimum_amount
  end

  def pending_balance
    commissions.pending.sum(:amount)
  end

  def lifetime_earnings
    commissions.where(status: [ :approved, :paid ]).sum(:amount)
  end

  def paid_out_total
    commissions.paid.sum(:amount)
  end

  def available_balance
    lifetime_earnings - paid_out_total
  end

  def has_pending_payout?
    payouts.pending.exists?
  end

  def last_payout
    payouts.recent.first
  end

  def can_request_payout?
    !has_pending_payout? && eligible_for_payout?(minimum_payout_amount || 100)
  end

  def unpaid_approved_commissions
    commissions.approved.where(payout_id: nil)
  end

  private

  def generate_code
    return if code.present?

    loop do
      self.code = generate_unique_code
      break unless Affiliate.exists?(code: code)
    end
  end

  def generate_unique_code
    # Generate a readable 8-character code
    SecureRandom.alphanumeric(8).upcase
  end

  def normalize_code
    self.code = code&.strip&.upcase
  end

  def password_required?
    # Password is required if it's being set through public signup
    # Not required for admin-created affiliates
    password.present? || password_confirmation.present?
  end

  def terms_required?
    # Terms acceptance is required only for self-signup
    # Check if being created through public controller (has password)
    password.present?
  end
end
