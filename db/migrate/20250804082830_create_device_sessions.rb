class CreateDeviceSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :device_sessions, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :integer
      t.string :device_id, null: false
      t.string :device_name
      t.string :device_platform
      t.string :client_version
      t.datetime :last_seen_at
      t.string :refresh_token_hash
      t.datetime :refresh_token_expires_at
      t.string :ip_address
      t.string :user_agent
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :device_sessions, :device_id
    add_index :device_sessions, :refresh_token_hash, unique: true
    add_index :device_sessions, [ :user_id, :device_id ], unique: true
    add_index :device_sessions, :active
  end
end
