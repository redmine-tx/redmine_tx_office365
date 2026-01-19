class CreateOffice365Storages < ActiveRecord::Migration[5.2]
  def change
    create_table :office365_storages do |t|
      t.string :key, null: false, limit: 255
      t.text :value
      t.string :value_type, default: 'string', limit: 50
      t.text :description
      t.timestamps null: false
    end

    add_index :office365_storages, :key, unique: true
  end
end

