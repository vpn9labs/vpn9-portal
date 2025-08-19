class DropDeviceSessions < ActiveRecord::Migration[8.0]
  def change
    drop_table :device_sessions
  end
end
