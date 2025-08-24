class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :plan
  has_many :payments, dependent: :destroy

  # Only include subscriptions from non-deleted users by default
  default_scope { joins(:user).merge(User.all) }

  enum :status, {
    active: 0,
    expired: 1,
    cancelled: 2,
    pending: 3
  }

  validates :started_at, presence: true
  validates :expires_at, presence: true
  validate :expires_at_after_started_at

  scope :current, -> { active.where("expires_at > ?", Time.current) }
  scope :expired_or_expiring, -> { where("expires_at <= ?", Time.current + 1.day) }

  def active?
    status == "active" && expires_at > Time.current
  end

  def days_remaining
    return 0 unless active?
    ((expires_at - Time.current) / 1.day).ceil
  end

  def expired?
    expires_at <= Time.current
  end

  def cancel!
    update!(status: :cancelled, cancelled_at: Time.current)
  end

  # Keep device access in sync with subscription changes
  after_commit :sync_user_device_statuses, on: [ :create, :update, :destroy ]

  private

  def expires_at_after_started_at
    return unless expires_at && started_at

    if expires_at <= started_at
      errors.add(:expires_at, "must be after the start date")
    end
  end

  def sync_user_device_statuses
    return unless user
    # Ensure devices reflect current subscription state and device limits
    Device.sync_statuses_for_user!(user)
  end
end
