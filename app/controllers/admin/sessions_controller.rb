class Admin::SessionsController < Admin::BaseController
  allow_unauthenticated_admin_access only: [ :new, :create ]
  layout "admin_auth", only: [ :new, :create ]

  def new
  end

  def create
    admin = Admin.find_by(email: params[:email])

    if admin && admin.authenticate(params[:password])
      start_new_admin_session_for(admin)
      redirect_to after_admin_authentication_url
    else
      flash.now[:alert] = "Invalid email or password"
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    terminate_admin_session
    redirect_to new_admin_session_path
  end
end
