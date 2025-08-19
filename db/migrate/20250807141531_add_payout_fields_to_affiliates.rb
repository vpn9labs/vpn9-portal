class AddPayoutFieldsToAffiliates < ActiveRecord::Migration[8.0]
  def change
    add_column :affiliates, :minimum_payout_amount, :decimal, precision: 10, scale: 2, default: 100, null: false
    add_column :affiliates, :notes, :text
  end
end
