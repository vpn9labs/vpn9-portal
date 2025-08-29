class AddLifetimeToPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :plans, :lifetime, :boolean, null: false, default: false
  end
end
