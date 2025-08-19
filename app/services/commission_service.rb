class CommissionService
  class << self
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

      # Auto-approve small commissions (configurable threshold)
      auto_approve_threshold = Rails.application.config.auto_approve_commission_threshold || 50.0
      if commission_amount <= auto_approve_threshold
        commission.approve!("Auto-approved: Under $#{auto_approve_threshold} threshold")
      end

      commission
    rescue => e
      Rails.logger.error "Failed to process commission for payment #{payment.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end

    def calculate_commission(payment, affiliate)
      base_amount = payment.amount.to_f
      commission_rate = affiliate.commission_rate.to_f / 100.0

      # Apply commission rate
      commission = base_amount * commission_rate

      # Round to 2 decimal places
      commission.round(2)
    end

    def approve_commission(commission, notes = nil)
      return false unless commission.pending?

      commission.approve!(notes)

      # Notify affiliate if email present
      if commission.affiliate.email.present?
        # AffiliateMailer.commission_approved(commission).deliver_later
      end

      true
    end

    def process_payout(affiliate, commission_ids = nil)
      commissions = affiliate.commissions.payable
      commissions = commissions.where(id: commission_ids) if commission_ids.present?

      return nil if commissions.empty?

      total_amount = commissions.sum(:amount)

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

      Rails.logger.info "Processed payout of $#{total_amount} for affiliate #{affiliate.code} (#{commissions.count} commissions)"

      {
        affiliate: affiliate,
        amount: total_amount,
        commission_count: commissions.count,
        transaction_id: transaction_id,
        currency: affiliate.payout_currency
      }
    rescue => e
      Rails.logger.error "Failed to process payout for affiliate #{affiliate.id}: #{e.message}"
      nil
    end

    def cancel_referral_commissions(referral, reason = nil)
      return unless referral

      # Cancel the referral
      referral.reject!(reason)

      # All pending commissions are cancelled by the referral model
      Rails.logger.info "Cancelled referral #{referral.id} and associated commissions: #{reason}"
    end
  end
end
