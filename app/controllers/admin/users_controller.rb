class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :edit, :update ]

  def index
    @users = User.includes(:subscriptions, :payments, :devices).order(created_at: :desc).page(params[:page])
  end

  def show
    @subscriptions = @user.subscriptions.includes(:plan).order(created_at: :desc)
    @payments = @user.payments.includes(:plan).order(created_at: :desc)
    @devices = @user.devices.order(created_at: :desc)
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email_address, :status)
  end
end
