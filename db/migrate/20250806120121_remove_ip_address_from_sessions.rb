class RemoveIpAddressFromSessions < ActiveRecord::Migration[8.0]
  def change
    remove_column :sessions, :ip_address, :string
  end
end
