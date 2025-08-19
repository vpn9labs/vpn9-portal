class Admin::PayoutsController < Admin::BaseController
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  def index
    @affiliates_with_balance = Affiliate.active
                                        .where("pending_balance > minimum_payout_amount")
                                        .includes(:commissions)
                                        .order(pending_balance: :desc)

    @recent_payouts = Commission.paid
                                .includes(:affiliate)
                                .order(paid_at: :desc)
                                .limit(20)

    @payout_stats = {
      total_pending: Affiliate.sum(:pending_balance),
      affiliates_awaiting: @affiliates_with_balance.count,
      paid_this_month: Commission.paid
                                 .where(paid_at: Date.current.beginning_of_month..)
                                 .sum(:amount),
      paid_total: Commission.paid.sum(:amount)
    }
  end

  def new
    @affiliate = Affiliate.find(params[:affiliate_id])
    @approved_commissions = @affiliate.commissions.approved
    @total_amount = @approved_commissions.sum(:amount)

    if @total_amount < @affiliate.minimum_payout_amount
      redirect_to admin_payouts_path,
                  alert: "Amount below minimum payout threshold"
      nil
    end
  end

  def create
    @affiliate = Affiliate.find(params[:affiliate_id])
    @commission_ids = params[:commission_ids] || []

    if @commission_ids.empty?
      # Process all approved commissions
      @commissions = @affiliate.commissions.approved
    else
      @commissions = @affiliate.commissions.approved.where(id: @commission_ids)
    end

    if @commissions.empty?
      redirect_to admin_payouts_path, alert: "No commissions to pay out"
      return
    end

    # Calculate total
    total_amount = @commissions.sum(:amount)

    # Create payout record (you might want a separate Payout model)
    transaction_id = process_payout(@affiliate, total_amount)

    if transaction_id
      # Mark commissions as paid
      @commissions.each do |commission|
        commission.mark_as_paid!(transaction_id)
      end

      redirect_to admin_payouts_path,
                  notice: "Payout of $#{total_amount} processed for #{@affiliate.name || @affiliate.code}"
    else
      redirect_to admin_payouts_path,
                  alert: "Failed to process payout"
    end
  end

  def export
    @start_date = begin
      params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
    rescue Date::Error
      30.days.ago.to_date
    end

    @end_date = begin
      params[:end_date] ? Date.parse(params[:end_date]) : Date.current
    rescue Date::Error
      Date.current
    end

    @payouts = Commission.paid
                         .includes(:affiliate)
                         .where(paid_at: @start_date.beginning_of_day..@end_date.end_of_day)
                         .order(paid_at: :desc)

    respond_to do |format|
      format.csv { send_data generate_csv(@payouts), filename: "payouts_#{@start_date}_#{@end_date}.csv" }
      format.json { render json: @payouts }
    end
  end

  private

  def process_payout(affiliate, amount)
    # This would integrate with your payment processor
    # For now, we'll simulate with a transaction ID

    case affiliate.payout_currency
    when "btc"
      # Process Bitcoin payment
      process_bitcoin_payout(affiliate, amount)
    when "eth"
      # Process Ethereum payment
      process_ethereum_payout(affiliate, amount)
    when "bank"
      # Process bank transfer
      process_bank_transfer(affiliate, amount)
    else
      # Default to manual processing
      "MANUAL-#{SecureRandom.hex(8)}"
    end
  end

  def process_bitcoin_payout(affiliate, amount)
    # Integrate with Bitcoin payment processor
    # This is a placeholder - implement actual BTC payment logic
    "BTC-#{SecureRandom.hex(8)}"
  end

  def process_ethereum_payout(affiliate, amount)
    # Integrate with Ethereum payment processor
    # This is a placeholder - implement actual ETH payment logic
    "ETH-#{SecureRandom.hex(8)}"
  end

  def process_bank_transfer(affiliate, amount)
    # Integrate with bank transfer API
    # This is a placeholder - implement actual bank transfer logic
    "BANK-#{SecureRandom.hex(8)}"
  end

  def generate_csv(payouts)
    require "csv"

    CSV.generate(headers: true) do |csv|
      csv << [ "Date", "Affiliate", "Email", "Amount", "Currency", "Transaction ID", "Payout Address" ]

      payouts.each do |payout|
        csv << [
          payout.paid_at.strftime("%Y-%m-%d %H:%M"),
          payout.affiliate.name || payout.affiliate.code,
          payout.affiliate.email,
          payout.amount,
          payout.currency,
          payout.payout_transaction_id,
          payout.affiliate.payout_address
        ]
      end
    end
  end

  def handle_not_found
    head :not_found
  end
end
