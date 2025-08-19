class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.integer :status, limit: 1, default: 0
      t.string :uid, null: false
      t.binary :secret_token
      t.binary :recovery_code
      t.string :email_address, null: true
      t.timestamp :last_seen

      t.timestamps
    end

    # enforce uniqueness only when email_address is not null
    add_index :users,
              :email_address,
              unique: true,
              where: "email_address IS NOT NULL"
  end
end
