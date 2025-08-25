#
# CommissionService handles affiliate commission lifecycle: creation, approval,
# payout grouping, and cancellation related to referrals.
#
# Responsibilities
# - Create a commission after a successful payment that is attributable to a
#   pending referral within the attribution window and for an active affiliate.
# - Auto‑approve small commissions under a configurable threshold.
# - Approve commissions manually (with optional notes).
# - Group payable commissions into a payout and mark them as paid.
# - Cancel a referral and its associated pending commissions.
#
# Configuration (Rails.application.config)
# - auto_approve_commission_threshold: Float (default: 50.0)
# - minimum_payout_amount: Float (default: 100.0)
#
# Domain model expectations
# - Referral#pending?, #within_attribution_window?, #convert!, #reject!
# - Affiliate#active?, #commission_rate, #payout_currency, #commissions
# - Commission scopes and transitions: .exists?, .payable, #approve!, #mark_as_paid!
# - Payment#successful?, #amount, #currency, #user
#
class CommissionService
  class << self
    # Process an incoming successful payment into a commission when applicable.
    #
    # Preconditions:
    # - Payment must be successful.
    # - User must have a pending referral within its attribution window.
    # - Affiliate must be active.
    # - No prior commission must exist for the same payment.
    #
    # Side effects:
    # - Marks referral converted on user's first successful payment.
    # - Creates a pending commission with computed amount and rate.
    # - Auto‑approves commission when amount <= auto_approve_commission_threshold.
    #
    # @param payment [Payment]
    # @return [Commission, nil] the created commission, or nil when not applicable or on error
    def process_payment(payment)
      return unless payment.successful?

      # Find referral for this user
      referral = payment.user.referral
      return unless referral

      # Check if referral is still pending
      return unless referral.pending?

      # Check if within attribution window
      return unless referral.within_attribution_window?

      # Get the affiliate
      affiliate = referral.affiliate
      return unless affiliate.active?

      # Check if commission already exists for this payment
      return if Commission.exists?(payment: payment)

      # Mark referral as converted if this is the first successful payment
      if payment.user.payments.successful.count == 1
        referral.convert!
      end

      # Calculate commission amount
      commission_amount = calculate_commission(payment, affiliate)

      # Create commission record
      commission = Commission.create!(
        affiliate: affiliate,
        payment: payment,
        referral: referral,
        amount: commission_amount,
        currency: payment.currency,
        commission_rate: affiliate.commission_rate,
        status: :pending
      )

      Rails.logger.info "Commission created: $#{commission_amount} for affiliate #{affiliate.code} from payment #{payment.id}"

      # Auto-approve small commissions when explicitly configured
      auto_approve_threshold = Rails.application.config.auto_approve_commission_threshold
      if auto_approve_threshold && commission_amount <= auto_approve_threshold
        commission.approve!("Auto-approved: Under $#{auto_approve_threshold} threshold")
      end

      commission
    rescue => e
      Rails.logger.error "Failed to process commission for payment #{payment.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end

    # Calculate monetary commission for a payment given an affiliate's rate.
    #
    # @param payment [Payment]
    # @param affiliate [Affiliate]
    # @return [Float] amount rounded to 2 decimal places
    def calculate_commission(payment, affiliate)
      base_amount = payment.amount.to_f
      commission_rate = affiliate.commission_rate.to_f / 100.0

      # Apply commission rate
      commission = base_amount * commission_rate

      # Round to 2 decimal places
      commission.round(2)
    end

    # Approve a pending commission.
    #
    # @param commission [Commission]
    # @param notes [String, nil] optional approval notes (e.g., reason)
    # @return [Boolean] true if approved, false when commission is not pending
    def approve_commission(commission, notes = nil)
      return false unless commission.pending?

      commission.approve!(notes)

      # Notify affiliate if email present
      if commission.affiliate.email.present?
        # AffiliateMailer.commission_approved(commission).deliver_later
      end

      true
    end

    # Process a payout for an affiliate by marking payable commissions as paid.
    #
    # Filters commissions to the provided list if commission_ids is given.
    # Enforces a minimum payout amount via configuration to avoid micro‑payouts.
    #
    # @param affiliate [Affiliate]
    # @param commission_ids [Array<Integer>, nil]
    # @return [Hash, nil] summary hash { affiliate:, amount:, commission_count:, transaction_id:, currency: } or nil when nothing to payout / below threshold
    def process_payout(affiliate, commission_ids = nil)
      scope = affiliate.commissions.payable
      scope = scope.where(id: commission_ids) if commission_ids.present?

      commissions = scope.to_a
      return nil if commissions.empty?

      total_amount = commissions.sum { |c| c.amount.to_f }

      # Check minimum payout threshold
      minimum_payout = Rails.application.config.minimum_payout_amount || 100.0
      if total_amount < minimum_payout
        Rails.logger.info "Payout amount $#{total_amount} below minimum $#{minimum_payout} for affiliate #{affiliate.code}"
        return nil
      end

      # Create payout record (would integrate with actual payout system)
      # For now, we just mark commissions as paid
      transaction_id = "PAYOUT-#{SecureRandom.hex(8).upcase}"

      commissions.each do |commission|
        commission.mark_as_paid!(transaction_id)
      end

      Rails.logger.info "Processed payout of $#{total_amount} for affiliate #{affiliate.code} (#{commissions.size} commissions)"

      {
        affiliate: affiliate,
        amount: total_amount,
        commission_count: commissions.size,
        transaction_id: transaction_id,
        currency: affiliate.payout_currency
      }
    rescue => e
      Rails.logger.error "Failed to process payout for affiliate #{affiliate.id}: #{e.message}"
      nil
    end

    # Cancel a referral and its associated pending commissions.
    #
    # @param referral [Referral]
    # @param reason [String, nil]
    # @return [void]
    def cancel_referral_commissions(referral, reason = nil)
      return unless referral

      # Cancel the referral
      referral.reject!(reason)

      # All pending commissions are cancelled by the referral model
      Rails.logger.info "Cancelled referral #{referral.id} and associated commissions: #{reason}"
    end
  end
end
