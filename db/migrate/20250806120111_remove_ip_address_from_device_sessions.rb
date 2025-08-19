class RemoveIpAddressFromDeviceSessions < ActiveRecord::Migration[8.0]
  def change
    remove_column :device_sessions, :ip_address, :string
  end
end
