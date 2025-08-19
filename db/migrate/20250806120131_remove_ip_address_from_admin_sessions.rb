class RemoveIpAddressFromAdminSessions < ActiveRecord::Migration[8.0]
  def change
    remove_column :admin_sessions, :ip_address, :string
  end
end
