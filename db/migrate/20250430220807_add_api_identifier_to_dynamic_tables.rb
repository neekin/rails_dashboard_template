class AddApiIdentifierToDynamicTables < ActiveRecord::Migration[8.0]
  def change
    add_column :dynamic_tables, :api_identifier, :string
    add_index :dynamic_tables, :api_identifier, unique: true
  end
end
