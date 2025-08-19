class Admin::DashboardController < Admin::BaseController
  def index
    @users_count = User.count
    @active_subscriptions_count = Subscription.current.count
    @total_payments = Payment.successful.count
    @recent_payments = Payment.successful.recent.limit(10).includes(:user, :plan)
    @recent_users = User.order(created_at: :desc).limit(10)
  end
end
