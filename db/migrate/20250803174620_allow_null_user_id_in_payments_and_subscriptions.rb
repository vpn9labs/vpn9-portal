class AllowNullUserIdInPaymentsAndSubscriptions < ActiveRecord::Migration[8.0]
  def change
    change_column_null :payments, :user_id, true
    change_column_null :subscriptions, :user_id, true
  end
end
