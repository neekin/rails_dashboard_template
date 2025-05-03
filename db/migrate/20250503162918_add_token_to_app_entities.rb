class AddTokenToAppEntities < ActiveRecord::Migration[8.0]
  def change
    add_column :app_entities, :token, :string
    add_index :app_entities, :token, unique: true
  end
end
