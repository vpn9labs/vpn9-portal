class RootController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  def index
    if params[:dismiss]
      session.delete(:show_credentials)
    end

    # If user is signed in, show dashboard view
    # Otherwise, show appropriate landing page based on parameters
    if authenticated?
      render :dashboard, layout: "application"
    else
      # Counts for teaser/live landing pages
      @launch_notifications_count = LaunchNotification.count
      # Check for special landing page versions
      if params[:live].present? || params[:full].present?
        # Show the full/live landing page when explicitly requested
        @cro_version = false
        @teaser_version = false
        render :landing
      elsif params[:cro].present?
        # Show CRO optimized version
        @cro_version = true
        render :landing_cro
      else
        # Default to teaser/coming soon page
        @teaser_version = true
        render :landing_teaser
      end
    end
  end
end
