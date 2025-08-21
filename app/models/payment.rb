class Payment < ApplicationRecord
  # Use UUID as primary key
  self.implicit_order_column = :created_at

  belongs_to :user
  belongs_to :plan
  belongs_to :subscription, optional: true
  has_one :commission

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
        subscription.expires_at = Time.current + plan.duration_days.days
      else
        # Extend existing subscription
        subscription.expires_at += plan.duration_days.days
      end

      subscription.status = :active
      subscription.save!

      # Link payment to subscription
      update!(subscription: subscription, paid_at: Time.current)
    end
  end

  # Update payment status from webhook
  def update_from_webhook!(webhook_data)
    case webhook_data["status"]
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

    self.transaction_id = webhook_data["transaction_id"]
    self.processor_data = webhook_data
    save!

    # Process subscription if payment is successful
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
