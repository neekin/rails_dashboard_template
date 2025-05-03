class CreateAppEntities < ActiveRecord::Migration[8.0]
  def change
    create_table :app_entities do |t|
      t.string :name
      t.text :description
      t.integer :status

      t.timestamps
    end
  end
end
