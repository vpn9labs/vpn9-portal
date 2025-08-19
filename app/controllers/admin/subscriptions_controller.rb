class Admin::SubscriptionsController < Admin::BaseController
  before_action :set_subscription, only: [ :show, :edit, :update ]
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found

  def index
    @subscriptions = Subscription.includes(:user, :plan).order(created_at: :desc).page(params[:page])
  end

  def show
    @payments = @subscription.payments.includes(:plan).order(created_at: :desc)
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

  def handle_not_found
    head :not_found
  end
end
