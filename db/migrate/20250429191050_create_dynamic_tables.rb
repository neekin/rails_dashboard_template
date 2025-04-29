class CreateDynamicTables < ActiveRecord::Migration[8.0]
  def change
    create_table :dynamic_tables do |t|
      t.string :table_name

      t.timestamps
    end
  end
end
