class CreateReferrals < ActiveRecord::Migration[8.0]
  def change
    create_table :referrals do |t|
      t.references :affiliate, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :referral_code # The code used at signup
      t.string :landing_page # First page visited
      t.string :ip_hash # Hashed IP for fraud detection
      t.datetime :clicked_at # When affiliate link was clicked
      t.datetime :converted_at # When user made first payment
      t.integer :status, default: 0 # pending, converted, rejected
      t.timestamps

      t.index [ :affiliate_id, :status ]
      t.index :user_id, unique: true, name: 'index_referrals_on_user_id_unique' # One referral per user
    end
  end
end
