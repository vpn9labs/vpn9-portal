class FixSoftDeleteImplementation < ActiveRecord::Migration[8.0]
  def change
    # Revert the null constraint changes - user_id should NOT be nullable
    change_column_null :payments, :user_id, false
    change_column_null :subscriptions, :user_id, false

    # Remove the deleted_user_email columns as they're no longer needed
    remove_column :payments, :deleted_user_email, :string
    remove_column :subscriptions, :deleted_user_email, :string

    # Remove the anonymized_email column from users - not needed with proper scoping
    remove_column :users, :anonymized_email, :string

    # Update foreign keys to use restrict instead of nullify
    # This prevents accidental hard deletion while maintaining referential integrity
    remove_foreign_key :payments, :users
    remove_foreign_key :subscriptions, :users

    add_foreign_key :payments, :users, on_delete: :restrict
    add_foreign_key :subscriptions, :users, on_delete: :restrict
  end
end
