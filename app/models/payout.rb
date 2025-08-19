class Payout < ApplicationRecord
  belongs_to :affiliate
  has_many :commissions, dependent: :nullify

  enum :status, {
    pending: 0,      # Initial request state
    approved: 1,     # Admin approved
    processing: 2,   # Payment being processed
    completed: 3,    # Successfully paid
    failed: 4,       # Payment failed
    cancelled: 5     # Cancelled by admin/affiliate
  }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :affiliate, presence: true
  validates :currency, presence: true
  validates :payout_method, presence: true
  validates :payout_address, presence: true

  before_validation :set_defaults_from_affiliate, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :requests, -> { where(status: [ :pending, :approved ]) }
  scope :completed_payouts, -> { where(status: :completed) }
  scope :needs_processing, -> { where(status: [ :approved, :processing ]) }

  def mark_as_approved!(admin_notes = nil)
    update!(
      status: :approved,
      approved_at: Time.current,
      admin_notes: admin_notes
    )
  end

  def mark_as_processing!
    update!(status: :processing, processed_at: Time.current)
  end

  def mark_as_completed!(transaction_id)
    transaction do
      update!(
        status: :completed,
        completed_at: Time.current,
        transaction_id: transaction_id
      )

      # Mark all associated commissions as paid
      commissions.each do |commission|
        commission.mark_as_paid!(transaction_id)
      end
    end
  end

  def mark_as_failed!(reason)
    transaction do
      update!(
        status: :failed,
        failed_at: Time.current,
        failure_reason: reason
      )

      # Release commissions back to approved state
      commissions.update_all(payout_id: nil)
    end
  end

  def mark_as_cancelled!(reason = nil)
    transaction do
      update!(
        status: :cancelled,
        cancelled_at: Time.current,
        failure_reason: reason
      )

      # Release commissions back to approved state
      commissions.update_all(payout_id: nil)
    end
  end

  def can_cancel?
    pending? || approved?
  end

  def can_approve?
    pending?
  end

  def can_process?
    approved?
  end

  private

  def set_defaults_from_affiliate
    return unless affiliate

    self.currency ||= "USD"
    self.payout_method ||= affiliate.payout_currency
    self.payout_address ||= affiliate.payout_address
  end
end
