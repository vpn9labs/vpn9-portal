class CreateLaunchNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :launch_notifications do |t|
      t.string :email, null: false
      t.string :ip_address
      t.string :user_agent
      t.string :referrer
      t.boolean :notified, default: false, null: false
      t.string :source # track which domain/campaign they came from
      t.jsonb :metadata, default: {} # for storing utm params, etc

      t.timestamps
    end

    add_index :launch_notifications, :email, unique: true
    add_index :launch_notifications, :notified
    add_index :launch_notifications, :created_at
  end
end
