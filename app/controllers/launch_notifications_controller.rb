class LaunchNotificationsController < ApplicationController
  allow_unauthenticated_access

  def create
    @notification = LaunchNotification.new(notification_params)

    # Store request information
    @notification.ip_address = request.remote_ip
    @notification.user_agent = request.user_agent
    @notification.referrer = request.referrer
    @notification.source = request.host
    @notification.request_params = params

    respond_to do |format|
      if @notification.save
        format.json {
          render json: {
            success: true,
            message: "You're on the list!",
            total_signups: LaunchNotification.count
          }
        }
        format.html {
          redirect_to root_path(teaser: 1),
                     notice: "Thank you! We'll notify you as soon as we launch."
        }
      else
        format.json {
          render json: {
            success: false,
            error: @notification.errors.full_messages.first
          }, status: :unprocessable_content
        }
        format.html {
          redirect_to root_path(teaser: 1),
                     alert: @notification.errors.full_messages.first
        }
      end
    end
  end

  private

  def notification_params
    params.permit(:email)
  end
end
