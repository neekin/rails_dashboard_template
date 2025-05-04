class RemoveTokenFromAppEntities < ActiveRecord::Migration[8.0]
  def change
    remove_column :app_entities, :token, :string
  end
end
