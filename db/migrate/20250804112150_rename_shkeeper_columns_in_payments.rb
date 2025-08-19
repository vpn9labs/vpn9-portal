class RenameShkeeperColumnsInPayments < ActiveRecord::Migration[8.0]
  def change
    # Check if columns exist before renaming (might have been partially applied)
    if column_exists?(:payments, :shkeeper_id)
      rename_column :payments, :shkeeper_id, :processor_id
    end

    if column_exists?(:payments, :shkeeper_data)
      rename_column :payments, :shkeeper_data, :processor_data
    end

    # Handle index rename safely
    if index_exists?(:payments, :shkeeper_id)
      remove_index :payments, :shkeeper_id
      add_index :payments, :processor_id, unique: true
    elsif index_exists?(:payments, :processor_id)
      # Already renamed, do nothing
    end
  end
end
