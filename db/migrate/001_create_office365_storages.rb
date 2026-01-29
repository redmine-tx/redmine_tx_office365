class CreateOffice365Storages < ActiveRecord::Migration[5.2]
  def up
    unless table_exists?(:office365_storages)
      create_table :office365_storages do |t|
        t.string :key, null: false, limit: 255
        t.text :value
        t.string :value_type, default: 'string', limit: 50
        t.text :description
        t.timestamps null: false
      end

      add_index :office365_storages, :key, unique: true unless index_exists?(:office365_storages, :key)
    end
  end

  def down
    if table_exists?(:office365_storages)
      remove_index :office365_storages, :key if index_exists?(:office365_storages, :key)
      drop_table :office365_storages
    end
  end
end
