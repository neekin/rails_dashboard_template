class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.string :apikey
      t.string :apisecret
      t.references :app_entity, null: false, foreign_key: true, type: :bigint
      t.timestamps
    end
    add_index :api_keys, :apikey, unique: true
  end
end
