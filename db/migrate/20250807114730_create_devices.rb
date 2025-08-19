class CreateDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :public_key, null: false

      t.timestamps
    end
    add_index :devices, :name, unique: true
    add_index :devices, :public_key, unique: true
  end
end
