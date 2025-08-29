class Payment < ApplicationRecord
  # Use UUID as primary key
  self.implicit_order_column = :created_at

  belongs_to :user
  belongs_to :plan
  belongs_to :subscription, optional: true
  has_one :commission
  has_many :webhook_logs, as: :webhookable

  # Only include payments from non-deleted users by default
  default_scope { joins(:user).merge(User.all) }

  enum :status, {
    pending: 0,
    partial: 1,
    paid: 2,
    overpaid: 3,
    expired: 4,
    failed: 5
  }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true

  scope :successful, -> { where(status: [ :paid, :overpaid ]) }
  scope :recent, -> { order(created_at: :desc) }

  def successful?
    paid? || overpaid?
  end

  def process_completion!
    return unless successful?

    ActiveRecord::Base.transaction do
      # Create or extend subscription
      subscription = user.subscriptions.current.first || user.subscriptions.build(plan: plan)

      if subscription.new_record?
        subscription.started_at = Time.current
        subscription.expires_at = plan.lifetime? ? (Time.current + 100.years) : (Time.current + plan.duration_days.days)
      else
        # Extend existing subscription (upgrade to lifetime if applicable)
        # If purchasing a different plan, move the subscription to that plan
        subscription.plan = plan if subscription.plan_id != plan.id

        if plan.lifetime?
          subscription.expires_at = Time.current + 100.years
        else
          subscription.expires_at += plan.duration_days.days
        end
      end

      subscription.status = :active
      subscription.save!

      # Link payment to subscription
      update!(subscription: subscription, paid_at: Time.current)
    end
  end

  # Update status without saving
  def update_status!(status)
    case status
    when "PAID"
      self.status = :paid
    when "PARTIAL"
      self.status = :partial
    when "OVERPAID"
      self.status = :overpaid
    when "EXPIRED"
      self.status = :expired
    else
      self.status = :failed
    end

    save!

    check_for_successful_payment!
  end

  # Update payment status from webhook
  def update_from_webhook!(webhook_data, request_ip)
    # Prevent replay attacks
    if webhook_logs.where(status: webhook_data["status"]).exists?
      raise "Duplicate webhook detected"
    end

    # Log the webhook
    webhook_logs.create!(
      status: webhook_data["status"],
      ip_address: request_ip,
      processed_at: Time.current
    )

    self.transaction_id = webhook_data["transaction_id"]
    self.processor_data = webhook_data
    update_status!(webhook_data["status"])
  end

  def check_for_successful_payment!
    if successful?
      process_completion!

      # Process affiliate commission
      CommissionService.process_payment(self)
    end
  end

  def generate_webhook_secret!
    update!(webhook_secret: SecureRandom.hex(32))
  end
end
