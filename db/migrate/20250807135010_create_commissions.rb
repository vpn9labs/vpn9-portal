class CreateCommissions < ActiveRecord::Migration[8.0]
  def change
    create_table :commissions do |t|
      t.references :affiliate, null: false, foreign_key: true
      t.references :payment, type: :uuid, null: false, foreign_key: true
      t.references :referral, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, default: 'USD'
      t.decimal :commission_rate, precision: 5, scale: 2 # Rate at time of commission
      t.integer :status, default: 0 # pending, approved, paid, cancelled
      t.datetime :approved_at
      t.datetime :paid_at
      t.string :payout_transaction_id
      t.text :notes
      t.timestamps

      t.index [ :affiliate_id, :status ]
      t.index :payment_id, unique: true, name: 'index_commissions_on_payment_id_unique' # One commission per payment
    end
  end
end
