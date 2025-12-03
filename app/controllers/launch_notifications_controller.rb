class LaunchNotificationsController < ApplicationController
  include FormTimingToken

  allow_unauthenticated_access
  rate_limit to: 5, within: 3.minutes, only: :create, with: -> {
    respond_to do |format|
      format.json { render json: { success: false, error: t("launch_notifications.rate_limit_exceeded") }, status: :too_many_requests }
      format.html { redirect_to root_path(teaser: 1), alert: t("launch_notifications.rate_limit_exceeded") }
    end
  } unless Rails.env.test?

  def create
    # Anti-bot check: honeypot field should be empty
    return reject_as_bot("honeypot") if params[:company].present?

    # Anti-bot check: timing validation (form must take at least 2.5s to fill)
    return reject_as_bot("timing") if too_fast_submission?

    @notification = LaunchNotification.new(notification_params)

    # Store request information
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

  def reject_as_bot(reason)
    Rails.logger.info("[AntiBot] Rejected launch notification signup: #{reason}")

    # Return fake success to not inform bots they were detected
    respond_to do |format|
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
    end
  end
end
