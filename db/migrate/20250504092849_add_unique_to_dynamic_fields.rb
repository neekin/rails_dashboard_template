class AddUniqueToDynamicFields < ActiveRecord::Migration[8.0]
  def change
    add_column :dynamic_fields, :unique, :boolean, default: false, null: false
  end
end
