class Admin::PayoutRequestsController < Admin::BaseController
  before_action :set_payout, only: [ :show, :approve, :reject, :process_payment ]

  def index
    @status_filter = params[:status] || "pending"
    @payouts = Payout.includes(:affiliate, :commissions)

    if @status_filter == "all"
      @payouts = @payouts.recent
    else
      @payouts = @payouts.where(status: @status_filter).recent
    end

    @payouts = @payouts.page(params[:page])

    # Statistics
    @stats = {
      pending_count: Payout.pending.count,
      pending_amount: Payout.pending.sum(:amount),
      approved_count: Payout.approved.count,
      approved_amount: Payout.approved.sum(:amount),
      completed_this_month: Payout.completed
                                  .where(completed_at: Date.current.beginning_of_month..)
                                  .sum(:amount)
    }
  end

  def show
    @commissions = @payout.commissions.includes(:payment, :referral)
  end

  def approve
    if @payout.can_approve?
      @payout.mark_as_approved!(params[:admin_notes])
      redirect_to admin_payout_requests_path,
                  notice: "Payout request ##{@payout.id} has been approved"
    else
      redirect_to admin_payout_requests_path,
                  alert: "Cannot approve this payout request"
    end
  end

  def reject
    if @payout.pending?
      reason = params[:rejection_reason].presence || "Admin rejected"
      @payout.mark_as_cancelled!(reason)
      redirect_to admin_payout_requests_path,
                  alert: "Payout request ##{@payout.id} has been rejected"
    else
      redirect_to admin_payout_requests_path,
                  alert: "Cannot reject this payout request"
    end
  end

  def process_payment
    if !@payout.can_process?
      redirect_to admin_payout_requests_path,
                  alert: "Cannot process this payout - must be approved first"
      return
    end

    # Mark as processing
    @payout.mark_as_processing!

    # Process actual payment based on method
    success, transaction_id = process_payout_payment(@payout)

    if success
      @payout.mark_as_completed!(transaction_id)
      redirect_to admin_payout_requests_path,
                  notice: "Payout ##{@payout.id} processed successfully. Transaction: #{transaction_id}"
    else
      @payout.mark_as_failed!("Payment processing failed")
      redirect_to admin_payout_requests_path,
                  alert: "Failed to process payout ##{@payout.id}"
    end
  end

  def bulk_approve
    payout_ids = params[:payout_ids] || []
    payouts = Payout.pending.where(id: payout_ids)

    approved_count = 0
    payouts.each do |payout|
      if payout.can_approve?
        payout.mark_as_approved!("Bulk approved")
        approved_count += 1
      end
    end

    redirect_to admin_payout_requests_path,
                notice: "#{approved_count} payout(s) approved"
  end

  def bulk_process
    payout_ids = params[:payout_ids] || []
    payouts = Payout.approved.where(id: payout_ids)

    processed_count = 0
    failed_count = 0

    payouts.each do |payout|
      payout.mark_as_processing!
      success, transaction_id = process_payout_payment(payout)

      if success
        payout.mark_as_completed!(transaction_id)
        processed_count += 1
      else
        payout.mark_as_failed!("Bulk processing failed")
        failed_count += 1
      end
    end

    message = "#{processed_count} payout(s) processed successfully"
    message += ", #{failed_count} failed" if failed_count > 0

    redirect_to admin_payout_requests_path, notice: message
  end

  private

  def set_payout
    @payout = Payout.find(params[:id])
  end

  def process_payout_payment(payout)
    # This would integrate with your payment processor
    # For now, we'll simulate with a transaction ID

    case payout.payout_method
    when "btc"
      process_bitcoin_payment(payout)
    when "eth"
      process_ethereum_payment(payout)
    when "usdt"
      process_usdt_payment(payout)
    when "bank"
      process_bank_transfer(payout)
    when "manual"
      process_manual_payment(payout)
    else
      [ false, nil ]
    end
  end

  def process_bitcoin_payment(payout)
    # TODO: Integrate with Bitcoin payment processor
    # This is a placeholder - implement actual BTC payment logic
    transaction_id = "BTC-#{SecureRandom.hex(8)}"
    [ true, transaction_id ]
  end

  def process_ethereum_payment(payout)
    # TODO: Integrate with Ethereum payment processor
    # This is a placeholder - implement actual ETH payment logic
    transaction_id = "ETH-#{SecureRandom.hex(8)}"
    [ true, transaction_id ]
  end

  def process_usdt_payment(payout)
    # TODO: Integrate with USDT payment processor
    # This is a placeholder - implement actual USDT payment logic
    transaction_id = "USDT-#{SecureRandom.hex(8)}"
    [ true, transaction_id ]
  end

  def process_bank_transfer(payout)
    # TODO: Integrate with bank transfer API
    # This is a placeholder - implement actual bank transfer logic
    transaction_id = "BANK-#{SecureRandom.hex(8)}"
    [ true, transaction_id ]
  end

  def process_manual_payment(payout)
    # Manual payment - admin will handle outside the system
    transaction_id = "MANUAL-#{SecureRandom.hex(8)}"
    [ true, transaction_id ]
  end
end
