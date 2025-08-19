class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.datetime :started_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :cancelled_at

      t.timestamps
    end

    add_index :subscriptions, :status
    add_index :subscriptions, :expires_at
  end
end
