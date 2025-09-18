class CreateApiRefreshTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_refresh_tokens, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :token_hash, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.string :client_label
      t.integer :usage_count, null: false, default: 0

      t.timestamps
    end

    add_index :api_refresh_tokens, :token_hash, unique: true
    add_index :api_refresh_tokens, :expires_at
  end
end
