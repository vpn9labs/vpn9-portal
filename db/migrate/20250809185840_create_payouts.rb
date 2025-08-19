class CreatePayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :payouts do |t|
      t.references :affiliate, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, default: 'USD', null: false
      t.integer :status, default: 0, null: false
      t.string :payout_method, null: false
      t.string :payout_address, null: false
      t.string :transaction_id
      t.datetime :approved_at
      t.datetime :processed_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.datetime :cancelled_at
      t.text :admin_notes
      t.text :failure_reason
      t.timestamps
    end

    add_index :payouts, :status
    add_index :payouts, [ :affiliate_id, :status ]
    add_index :payouts, :transaction_id

    # Add payout reference to commissions table
    add_reference :commissions, :payout, foreign_key: true
  end
end
