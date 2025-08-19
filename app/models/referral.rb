class Referral < ApplicationRecord
  belongs_to :affiliate
  belongs_to :user
  has_many :commissions, dependent: :destroy

  enum :status, { pending: 0, converted: 1, rejected: 2 }

  validates :user_id, uniqueness: true
  validates :ip_hash, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :converted, -> { where(status: :converted) }
  scope :within_days, ->(days) { where("created_at > ?", days.days.ago) }
  scope :within_attribution_window, -> {
    joins(:affiliate)
      .where("referrals.created_at > NOW() - INTERVAL '1 day' * affiliates.attribution_window_days")
  }

  before_validation :set_clicked_at, on: :create

  def within_attribution_window?
    return false unless affiliate
    created_at > affiliate.attribution_window_days.days.ago
  end

  def days_since_click
    ((Time.current - created_at) / 1.day).round
  end

  def convert!
    return if converted?

    update!(
      status: :converted,
      converted_at: Time.current
    )

    # Mark the affiliate click as converted if we tracked it
    if ip_hash.present?
      affiliate.affiliate_clicks
        .where(ip_hash: ip_hash)
        .where("created_at >= ?", 1.hour.before(created_at))
        .update_all(converted: true)
    end
  end

  def reject!(reason = nil)
    return if rejected?

    transaction do
      update!(status: :rejected)

      # Cancel any pending commissions
      commissions.pending.update_all(
        status: :cancelled,
        notes: reason || "Referral rejected"
      )
    end
  end

  private

  def set_clicked_at
    self.clicked_at ||= created_at || Time.current
  end
end
