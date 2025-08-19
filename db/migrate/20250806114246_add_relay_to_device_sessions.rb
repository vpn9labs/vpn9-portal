class AddRelayToDeviceSessions < ActiveRecord::Migration[8.0]
  def change
    add_reference :device_sessions, :relay, null: true, foreign_key: true
    add_column :device_sessions, :connected_at, :datetime
    add_column :device_sessions, :disconnected_at, :datetime

    add_index :device_sessions, :connected_at
  end
end
