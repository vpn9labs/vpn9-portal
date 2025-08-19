class CreateRelays < ActiveRecord::Migration[8.0]
  def change
    create_table :relays do |t|
      t.string :name
      t.string :hostname
      t.string :ipv4_address
      t.string :ipv6_address
      t.string :public_key
      t.integer :port
      t.integer :status
      t.references :location, null: false, foreign_key: true

      t.timestamps
    end
  end
end
