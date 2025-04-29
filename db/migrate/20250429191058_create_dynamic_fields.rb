class CreateDynamicFields < ActiveRecord::Migration[8.0]
  def change
    create_table :dynamic_fields do |t|
      t.references :dynamic_table, null: false, foreign_key: true
      t.string :name
      t.string :field_type
      t.boolean :required

      t.timestamps
    end
  end
end
