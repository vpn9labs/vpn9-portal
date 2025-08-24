class AddStatusToDevices < ActiveRecord::Migration[8.0]
  def change
    add_column :devices, :status, :integer, default: 0, null: false
    add_index :devices, :status
    add_index :devices, [ :user_id, :status ]

    # Backfill existing devices conservatively to inactive, then
    # activate up to plan limits for users with active subscriptions.
    reversible do |dir|
      dir.up do
        say_with_time "Backfilling device statuses" do
          # Set all to inactive first
          execute <<~SQL
            UPDATE devices SET status = 0
          SQL

          # For each user with an active, non-expired subscription, activate up to device_limit
          # Use application code for clarity and safety
          begin
            Device.reset_column_information
            User.find_each do |user|
              Device.sync_statuses_for_user!(user) if user.respond_to?(:has_active_subscription?)
            end
          rescue => e
            say "Warning: could not backfill per-user device statuses: #{e.class}: #{e.message}", true
          end
        end
      end
    end
  end
end
