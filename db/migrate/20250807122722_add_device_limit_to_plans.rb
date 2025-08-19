class AddDeviceLimitToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :device_limit, :integer, default: 5, null: false

    # Update existing plans to have default device limit
    reversible do |dir|
      dir.up do
        Plan.update_all(device_limit: 5)
      end
    end
  end
end
