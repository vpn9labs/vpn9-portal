class CreateAffiliates < ActiveRecord::Migration[8.0]
  def change
    create_table :affiliates do |t|
      t.string :code, null: false
      t.string :name
      t.string :email
      t.string :payout_address # Crypto address for payouts
      t.string :payout_currency, default: 'btc' # btc, eth, usdt, etc.
      t.decimal :commission_rate, precision: 5, scale: 2, default: 20.0 # Percentage
      t.integer :status, default: 0 # active, suspended, terminated
      t.decimal :lifetime_earnings, precision: 10, scale: 2, default: 0
      t.decimal :pending_balance, precision: 10, scale: 2, default: 0
      t.decimal :paid_out_total, precision: 10, scale: 2, default: 0
      t.integer :cookie_duration_days, default: 30
      t.integer :attribution_window_days, default: 30
      t.json :settings # Additional configuration
      t.timestamps

      t.index :code, unique: true
      t.index :status
      t.index :email
    end
  end
end
