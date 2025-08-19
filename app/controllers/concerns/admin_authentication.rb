module AdminAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_admin_authentication
    helper_method :admin_authenticated?
  end

  class_methods do
    def allow_unauthenticated_admin_access(**options)
      skip_before_action :require_admin_authentication, **options
    end
  end

  private
    def admin_authenticated?
      resume_admin_session
    end

    def require_admin_authentication
      resume_admin_session || request_admin_authentication
    end

    def resume_admin_session
      Current.admin_session ||= find_admin_session_by_cookie
    end

    def find_admin_session_by_cookie
      if cookies.signed[:admin_session_id]
        AdminSession.find_by(id: cookies.signed[:admin_session_id])
      end
    end

    def request_admin_authentication
      session[:admin_return_to] = request.url
      redirect_to new_admin_session_path
    end

    def after_admin_authentication_url
      session.delete(:admin_return_to) || admin_root_url
    end

    def start_new_admin_session_for(admin)
      admin.admin_sessions.create!(
        user_agent: request.user_agent
      ).tap do |admin_session|
        Current.admin_session = admin_session
        cookies.signed.permanent[:admin_session_id] = {
          value: admin_session.id,
          httponly: true,
          same_site: :lax
        }
      end
    end

    def terminate_admin_session
      Current.admin_session.destroy
      cookies.delete(:admin_session_id)
    end
end
