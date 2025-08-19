class CreateAffiliateClicks < ActiveRecord::Migration[8.0]
  def change
    create_table :affiliate_clicks do |t|
      t.references :affiliate, null: false, foreign_key: true
      t.string :ip_hash # Hashed IP
      t.string :user_agent_hash # Hashed user agent
      t.string :landing_page
      t.string :referrer
      t.boolean :converted, default: false
      t.timestamps

      t.index [ :affiliate_id, :created_at ]
      t.index [ :ip_hash, :created_at ]
    end
  end
end
