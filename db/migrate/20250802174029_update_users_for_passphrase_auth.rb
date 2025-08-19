class UpdateUsersForPassphraseAuth < ActiveRecord::Migration[8.0]
  def change
    # Add new passphrase column
    add_column :users, :passphrase_hash, :binary

    # Remove old authentication columns after data migration
    remove_column :users, :uid, :string
    remove_column :users, :secret_token, :binary

    # Keep recovery_code for account recovery
    # Keep email_address as optional field
  end
end
