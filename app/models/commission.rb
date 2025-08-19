class Commission < ApplicationRecord
  belongs_to :affiliate
  belongs_to :payment
  belongs_to :referral
  belongs_to :payout, optional: true

  enum :status, { pending: 0, approved: 1, paid: 2, cancelled: 3 }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :commission_rate, presence: true, numericality: { in: 0..100 }
  validates :payment_id, uniqueness: true

  scope :payable, -> { approved.where(paid_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :for_period, ->(start_date, end_date) {
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
  }

  before_validation :set_commission_rate, on: :create

  def approve!(admin_notes = nil)
    return if approved? || paid?

    update!(
      status: :approved,
      approved_at: Time.current,
      notes: [ notes, admin_notes ].compact.join("\n")
    )
  end

  def cancel!(reason = nil)
    return if cancelled?

    update!(
      status: :cancelled,
      notes: [ notes, reason ].compact.join("\n")
    )
  end

  def mark_as_paid!(transaction_id = nil)
    return if paid?

    update!(
      status: :paid,
      paid_at: Time.current,
      payout_transaction_id: transaction_id
    )
  end

  private

  def set_commission_rate
    self.commission_rate ||= affiliate&.commission_rate
  end
end
