class RemoveIpAddressFromLaunchNotifications < ActiveRecord::Migration[8.0]
  def change
    remove_column :launch_notifications, :ip_address, :string
  end
end
