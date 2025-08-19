require "csv"

class Admin::LaunchNotificationsController < Admin::BaseController
  before_action :set_launch_notification, only: [ :show, :destroy ]

  def index
    @launch_notifications = LaunchNotification.all.order(created_at: :desc)
    @total_count = @launch_notifications.count

    # Apply filters if present
    if params[:search].present?
      @launch_notifications = @launch_notifications.where("email ILIKE ?", "%#{params[:search]}%")
    end

    if params[:date_from].present?
      @launch_notifications = @launch_notifications.where("created_at >= ?", params[:date_from])
    end

    if params[:date_to].present?
      @launch_notifications = @launch_notifications.where("created_at <= ?", params[:date_to])
    end

    @launch_notifications = @launch_notifications.page(params[:page])
  end

  def show
  end

  def destroy
    @launch_notification.destroy
    redirect_to admin_launch_notifications_path, notice: "Launch notification signup was successfully removed."
  end

  def export
    @launch_notifications = LaunchNotification.all.order(created_at: :desc)

    respond_to do |format|
      format.csv do
        send_data generate_csv(@launch_notifications),
                  filename: "launch_notifications_#{Date.current}.csv",
                  type: "text/csv"
      end
    end
  end

  def stats
    @total_signups = LaunchNotification.count
    @signups_today = LaunchNotification.where("created_at >= ?", Time.current.beginning_of_day).count
    @signups_this_week = LaunchNotification.where("created_at >= ?", 1.week.ago).count
    @signups_this_month = LaunchNotification.where("created_at >= ?", 1.month.ago).count

    # Daily signups for the last 30 days (grouped by date)
    @daily_signups = LaunchNotification
      .where("created_at >= ?", 30.days.ago)
      .group("DATE(created_at)")
      .count
      .transform_keys { |date| Date.parse(date.to_s) }
  end

  private

  def set_launch_notification
    @launch_notification = LaunchNotification.find(params[:id])
  end

  def generate_csv(notifications)
    CSV.generate(headers: true) do |csv|
      csv << [ "Email", "IP Address", "User Agent", "Referrer", "UTM Source", "UTM Campaign", "Signed Up At" ]

      notifications.each do |notification|
        metadata = notification.metadata || {}
        csv << [
          notification.email,
          metadata["ip_address"],
          metadata["user_agent"],
          metadata["referrer"],
          metadata["utm_source"],
          metadata["utm_campaign"],
          notification.created_at.strftime("%Y-%m-%d %H:%M:%S")
        ]
      end
    end
  end
end
