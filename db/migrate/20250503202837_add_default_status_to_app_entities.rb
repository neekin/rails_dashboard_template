class AddDefaultStatusToAppEntities < ActiveRecord::Migration[8.0]
  def change
    change_column_default :app_entities, :status, from: nil, to: 0
  end
end
