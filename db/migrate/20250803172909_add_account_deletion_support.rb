class AddAccountDeletionSupport < ActiveRecord::Migration[8.0]
  def change
    # Add soft delete to users
    add_column :users, :deleted_at, :datetime
    add_index :users, :deleted_at

    # Add anonymized user data storage for deleted accounts
    add_column :users, :anonymized_email, :string
    add_column :users, :deletion_reason, :text

    # Remove foreign key constraints that would prevent user deletion
    remove_foreign_key :payments, :users
    remove_foreign_key :subscriptions, :users
    remove_foreign_key :sessions, :users

    # Re-add foreign keys with nullify option for payments and subscriptions
    add_foreign_key :payments, :users, on_delete: :nullify
    add_foreign_key :subscriptions, :users, on_delete: :nullify

    # Sessions should cascade delete
    add_foreign_key :sessions, :users, on_delete: :cascade

    # Add deleted user reference columns to preserve audit trail
    add_column :payments, :deleted_user_email, :string
    add_column :subscriptions, :deleted_user_email, :string

    # Add indexes for querying deleted user data
    add_index :payments, :deleted_user_email
    add_index :subscriptions, :deleted_user_email
  end
end
