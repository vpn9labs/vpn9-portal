class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.references :subscription, foreign_key: true

      # Payment details
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.integer :status, default: 0, null: false

      # SHKeeper specific fields
      t.string :shkeeper_id
      t.string :crypto_currency
      t.decimal :crypto_amount, precision: 18, scale: 8
      t.string :payment_address
      t.jsonb :shkeeper_data, default: {}

      # Transaction tracking
      t.string :transaction_id
      t.datetime :paid_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :payments, :shkeeper_id, unique: true
    add_index :payments, :status
    add_index :payments, :paid_at
  end
end
