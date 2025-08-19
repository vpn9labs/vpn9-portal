class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :currency, default: 'USD', null: false
      t.integer :duration_days, null: false
      t.boolean :active, default: true, null: false
      t.jsonb :features, default: {}

      t.timestamps
    end

    add_index :plans, :active
  end
end
