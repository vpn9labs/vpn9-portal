class Affiliates::EarningsController < Affiliates::BaseController
  def index
    @commissions = @current_affiliate.commissions
                                     .includes(:payment, :referral)
                                     .order(created_at: :desc)
                                     .page(params[:page])

    @earnings_summary = {
      pending: @current_affiliate.commissions.pending.sum(:amount),
      approved: @current_affiliate.commissions.approved.sum(:amount),
      paid: @current_affiliate.commissions.paid.sum(:amount),
      cancelled: @current_affiliate.commissions.cancelled.sum(:amount),
      available_balance: @current_affiliate.available_balance,
      lifetime_earnings: @current_affiliate.lifetime_earnings
    }

    @monthly_earnings = calculate_monthly_earnings
  end

  def payouts
    @payouts = @current_affiliate.payouts
                                 .order(created_at: :desc)
                                 .page(params[:page])
  end

  def request_payout
    # Check if affiliate already has a pending payout
    if @current_affiliate.has_pending_payout?
      redirect_to affiliates_earnings_path,
                  alert: "You already have a pending payout request. Please wait for it to be processed."
      return
    end

    # Check if affiliate meets minimum payout requirements
    minimum_amount = @current_affiliate.minimum_payout_amount || 100
    if !@current_affiliate.eligible_for_payout?(minimum_amount)
      available = @current_affiliate.available_balance
      redirect_to affiliates_earnings_path,
                  alert: "Your available balance ($#{available}) is below the minimum payout amount ($#{minimum_amount})"
      return
    end

    # Check if affiliate has payout details configured
    if @current_affiliate.payout_address.blank? || @current_affiliate.payout_currency.blank?
      redirect_to edit_affiliates_profile_path,
                  alert: "Please configure your payout details in your profile before requesting a payout"
      return
    end

    # Get all unpaid approved commissions
    eligible_commissions = @current_affiliate.unpaid_approved_commissions

    if eligible_commissions.empty?
      redirect_to affiliates_earnings_path,
                  alert: "No eligible commissions available for payout"
      return
    end

    amount = eligible_commissions.sum(:amount)

    # Create payout request
    payout = @current_affiliate.payouts.build(
      amount: amount,
      currency: "USD",
      status: :pending,
      payout_method: @current_affiliate.payout_currency,
      payout_address: @current_affiliate.payout_address
    )

    if payout.save
      # Associate commissions with this payout
      eligible_commissions.update_all(payout_id: payout.id)

      # TODO: Send notification email to admin
      # AdminMailer.new_payout_request(payout).deliver_later

      redirect_to affiliates_earnings_path,
                  notice: "Payout request for $#{'%.2f' % amount} has been submitted successfully. You'll be notified once it's processed."
    else
      redirect_to affiliates_earnings_path,
                  alert: "Failed to create payout request: #{payout.errors.full_messages.join(', ')}"
    end
  end

  def cancel_payout
    @payout = @current_affiliate.payouts.find(params[:id])

    if @payout.can_cancel?
      @payout.mark_as_cancelled!("Cancelled by affiliate")
      redirect_to payouts_affiliates_earnings_path,
                  notice: "Payout request has been cancelled successfully"
    else
      redirect_to payouts_affiliates_earnings_path,
                  alert: "This payout request cannot be cancelled"
    end
  end

  private

  def calculate_monthly_earnings
    # Group by month manually without groupdate gem
    monthly_data = {}
    12.times do |i|
      month = (Date.current - i.months).beginning_of_month
      monthly_data[month.strftime("%B %Y")] = @current_affiliate.commissions
                                                                  .approved
                                                                  .where(created_at: month..month.end_of_month)
                                                                  .sum(:amount)
    end
    monthly_data
  end
end
