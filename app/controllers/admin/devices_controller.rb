class Admin::DevicesController < Admin::BaseController
  before_action :set_user
  before_action :set_device

  def destroy
    device_name = @device.name
    @device.destroy
    redirect_to admin_user_path(@user), notice: "Device '#{device_name}' was successfully removed."
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def set_device
    @device = @user.devices.find(params[:id])
  end
end
