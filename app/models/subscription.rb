#
# Subscription models a user's paid access to the VPN service.
#
# Responsibilities
# - Associates a User with a Plan over a time window (`started_at`..`expires_at`).
# - Tracks lifecycle via `status` enum (`active`, `expired`, `cancelled`, `pending`).
# - Provides helpers/scopes to check activity and remaining time.
# - Synchronizes device access on changes and on time-based expiration sweeps.
#
# Access and Device Sync
# - Devices are allowed only when the user has a current subscription
#   (status `active` and `expires_at` in the future).
# - After any create/update/destroy to a subscription, the user's device
#   statuses are recalculated to match plan limits and subscription state.
# - Time-based expirations are handled by `.sync_expirations!`, intended to run
#   periodically (see `config/crontab` entry invoking `subscriptions:expire`).
#
# @!attribute [rw] status
#   Lifecycle state of the subscription.
#   One of: `active`, `expired`, `cancelled`, `pending`.
#   @return [String]
# @!attribute [rw] started_at
#   Start timestamp of subscription coverage.
#   @return [ActiveSupport::TimeWithZone]
# @!attribute [rw] expires_at
#   End timestamp for subscription coverage; access ends at/after this time.
#   @return [ActiveSupport::TimeWithZone]
# @!attribute [rw] cancelled_at
#   Time when a subscription was explicitly cancelled (optional).
#   @return [ActiveSupport::TimeWithZone, nil]
# @!attribute [r] user_id
#   Owning user foreign key.
#   @return [String] UUID
# @!attribute [r] plan_id
#   Associated plan foreign key.
#   @return [String] UUID
#
class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :plan
  has_many :payments, dependent: :nullify

  # Only include subscriptions from non-deleted users by default
  default_scope { joins(:user).merge(User.all) }

  # Lifecycle state
  enum :status, {
    active: 0,
    expired: 1,
    cancelled: 2,
    pending: 3
  }

  validates :started_at, presence: true
  validates :expires_at, presence: true
  validate :expires_at_after_started_at

  # Subscriptions that are currently valid (status active and not expired)
  scope :current, -> { active.where("subscriptions.expires_at > ?", Time.current) }
  # Subscriptions that have expired or will expire within 24 hours
  scope :expired_or_expiring, -> { where("subscriptions.expires_at <= ?", Time.current + 1.day) }

  # Keep device access in sync with subscription changes
  # - Always sync on create/destroy
  # - On update, sync only when fields affecting access/limits change
  after_commit :sync_user_device_statuses, on: [ :create, :destroy ]
  after_commit :sync_user_device_statuses_if_relevant, on: :update

  # Whether this subscription currently grants access.
  # @return [Boolean]
  def active?
    status == "active" && expires_at > Time.current
  end

  # Days remaining until expiration (ceil, minimum 0 when inactive)
  # @return [Integer]
  def days_remaining
    return 0 unless active?
    ((expires_at - Time.current) / 1.day).ceil
  end

  # Whether this subscription has passed its expiration time.
  # @return [Boolean]
  def expired?
    expires_at <= Time.current
  end

  # Cancel the subscription now and record the cancellation time.
  # @return [void]
  def cancel!
    update!(status: :cancelled, cancelled_at: Time.current)
  end

  # Mark all `active` subscriptions that have reached `expires_at` as `expired`
  # and deactivate devices for those users.
  # Intended to be run periodically (hourly via cron).
  #
  # @return [Integer] number of affected users whose devices were resynced
  def self.sync_expirations!
    to_expire = where(status: statuses[:active]).where("subscriptions.expires_at <= ?", Time.current)
    return 0 if to_expire.none?

    # Collect affected users before bulk update to avoid N queries with callbacks
    user_ids = to_expire.distinct.pluck(:user_id)

    # Update status in bulk (no callbacks), then ensure devices are synced per user
    to_expire.update_all(status: statuses[:expired])

    User.where(id: user_ids).find_each do |u|
      Device.sync_statuses_for_user!(u)
    end

    user_ids.length
  end

  private

  # Validation: `expires_at` must be after `started_at`.
  # @return [void]
  def expires_at_after_started_at
    return unless expires_at && started_at

    if expires_at <= started_at
      errors.add(:expires_at, "must be after the start date")
    end
  end

  # After-commit hook to recalculate device access for the owning user.
  # @return [void]
  def sync_user_device_statuses
    return unless user
    # Ensure devices reflect current subscription state and device limits
    Device.sync_statuses_for_user!(user)
  end

  # Only sync when relevant attributes change (status, plan, or expiry)
  def sync_user_device_statuses_if_relevant
    return unless user
    changes = previous_changes || {}
    relevant = changes.key?("status") || changes.key?("plan_id") || changes.key?("expires_at")
    return unless relevant
    Device.sync_statuses_for_user!(user)
  end
end
