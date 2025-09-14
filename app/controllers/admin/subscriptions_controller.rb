class Admin::SubscriptionsController < Admin::BaseController
  before_action :set_subscription, only: [ :show, :edit, :update ]
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found

  def index
    @subscriptions = Subscription.includes(:user, :plan).order(created_at: :desc).page(params[:page])
  end

  def show
    @payments = @subscription.payments.includes(:plan).order(created_at: :desc)
  end

  def new
    @subscription = Subscription.new
    # Pre-select user/plan if passed in query (e.g., from user page)
    @subscription.user_id = params[:user_id] if params[:user_id].present?
    @subscription.plan_id = params[:plan_id] if params[:plan_id].present?
    @subscription.status = :active
    @subscription.started_at = Time.current
  end

  def create
    @subscription = Subscription.new(create_subscription_params)

    # Default to active subscription from now if not provided
    @subscription.status ||= :active
    @subscription.started_at ||= Time.current

    # Auto-calculate expires_at from plan if not provided
    if @subscription.expires_at.blank?
      if @subscription.plan&.lifetime?
        @subscription.expires_at = Time.current + 100.years
      elsif @subscription.plan&.duration_days.present?
        @subscription.expires_at = Time.current + @subscription.plan.duration_days.days
      end
    end

    if @subscription.save
      redirect_to admin_subscription_path(@subscription), notice: "Subscription was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @subscription.update(subscription_params)
      redirect_to admin_subscription_path(@subscription), notice: "Subscription was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_subscription
    @subscription = Subscription.find(params[:id])
  end

  def subscription_params
    params.require(:subscription).permit(:status, :expires_at)
  end

  def create_subscription_params
    params.require(:subscription).permit(:user_id, :plan_id, :status, :started_at, :expires_at)
  end

  def handle_not_found
    head :not_found
  end
end
