class CreateLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :locations do |t|
      t.string :country_code, limit: 2
      t.string :city
      t.decimal :latitude
      t.decimal :longitude

      t.timestamps
    end
  end
end
