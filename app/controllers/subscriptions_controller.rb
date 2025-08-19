class SubscriptionsController < ApplicationController
  def index
    @current_subscription = Current.user.current_subscription
    @past_subscriptions = Current.user.subscriptions
                                     .where.not(id: @current_subscription&.id)
                                     .order(created_at: :desc)
    @recent_payments = Current.user.payments.recent.limit(10)
  end

  def show
    @subscription = Current.user.subscriptions.find(params[:id])
    @payments = @subscription.payments.order(created_at: :desc)
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Subscription not found"
  end

  def cancel
    @subscription = Current.user.subscriptions.find(params[:id])

    if @subscription.cancelled?
      redirect_to subscriptions_path, alert: "Subscription is already cancelled"
    elsif @subscription.active?
      @subscription.cancel!
      redirect_to subscriptions_path, notice: "Subscription cancelled successfully"
    else
      redirect_to subscriptions_path, alert: "Cannot cancel this subscription"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to subscriptions_path, alert: "Subscription not found"
  end
end
