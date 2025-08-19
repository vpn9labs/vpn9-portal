class DevicesController < ApplicationController
  before_action :set_device, only: [ :destroy ]

  def index
    @devices = Current.user.devices.order(created_at: :desc)
  end

  def destroy
    device_name = @device.name
    @device.destroy
    redirect_to devices_path, notice: "Device '#{device_name}' removed"
  end

  private

  def set_device
    @device = Current.user.devices.find(params[:id])
  end
end
