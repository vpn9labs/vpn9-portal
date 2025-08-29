class AllowNullDurationDaysOnPlans < ActiveRecord::Migration[7.1]
  def change
    change_column_null :plans, :duration_days, true
  end
end
