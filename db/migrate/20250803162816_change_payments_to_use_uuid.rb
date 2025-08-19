class ChangePaymentsToUseUuid < ActiveRecord::Migration[8.0]
  def up
    # First, we need to handle foreign key constraints
    remove_foreign_key :payments, :users
    remove_foreign_key :payments, :plans

    # Create a temporary UUID column
    add_column :payments, :uuid, :uuid, default: "gen_random_uuid()", null: false

    # Add indexes for the UUID
    add_index :payments, :uuid, unique: true

    # Remove the old primary key
    execute "ALTER TABLE payments DROP CONSTRAINT payments_pkey CASCADE"

    # Remove the old id column
    remove_column :payments, :id

    # Rename uuid to id
    rename_column :payments, :uuid, :id

    # Set the new primary key
    execute "ALTER TABLE payments ADD PRIMARY KEY (id)"

    # Re-add foreign keys
    add_foreign_key :payments, :users
    add_foreign_key :payments, :plans
  end

  def down
    # This is a destructive operation and should be carefully considered
    raise ActiveRecord::IrreversibleMigration, "Cannot reverse UUID migration safely"
  end
end
