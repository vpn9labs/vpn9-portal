class Admin::CommissionsController < Admin::BaseController
  before_action :set_commission, only: [ :show, :approve, :cancel ]

  def index
    @commissions = Commission.includes(:affiliate, :payment, :referral)

    # Filter by status
    if params[:status].present?
      @commissions = @commissions.by_status(params[:status])
    end

    # Filter by affiliate
    if params[:affiliate_id].present?
      @commissions = @commissions.where(affiliate_id: params[:affiliate_id])
    end

    # Filter by date range
    if params[:start_date].present? && params[:end_date].present?
      @commissions = @commissions.for_period(
        Date.parse(params[:start_date]),
        Date.parse(params[:end_date])
      )
    end

    @commissions = @commissions.order(created_at: :desc).page(params[:page])

    # Calculate totals
    @totals = {
      pending: Commission.pending.sum(:amount),
      approved: Commission.approved.sum(:amount),
      paid: Commission.paid.sum(:amount),
      cancelled: Commission.cancelled.sum(:amount)
    }
  end

  def show
    @affiliate = @commission.affiliate
    @payment = @commission.payment
    @referral = @commission.referral
    @user = @referral&.user
  end

  def approve
    if @commission.pending?
      @commission.approve!(params[:notes])
      redirect_to admin_commissions_path, notice: "Commission approved"
    else
      redirect_to admin_commissions_path, alert: "Commission cannot be approved"
    end
  end

  def cancel
    if @commission.pending? || @commission.approved?
      @commission.cancel!(params[:reason])
      redirect_to admin_commissions_path, notice: "Commission cancelled"
    else
      redirect_to admin_commissions_path, alert: "Commission cannot be cancelled"
    end
  end

  def bulk_approve
    commission_ids = params[:commission_ids] || []
    approved_count = 0

    Commission.where(id: commission_ids, status: :pending).find_each do |commission|
      commission.approve!("Bulk approved by admin")
      approved_count += 1
    end

    redirect_to admin_commissions_path,
                notice: "#{approved_count} commissions approved"
  end

  def bulk_cancel
    commission_ids = params[:commission_ids] || []
    cancelled_count = 0
    reason = params[:reason] || "Bulk cancelled by admin"

    Commission.where(id: commission_ids).where.not(status: :paid).find_each do |commission|
      commission.cancel!(reason)
      cancelled_count += 1
    end

    redirect_to admin_commissions_path,
                notice: "#{cancelled_count} commissions cancelled"
  end

  private

  def set_commission
    @commission = Commission.find(params[:id])
  end
end
