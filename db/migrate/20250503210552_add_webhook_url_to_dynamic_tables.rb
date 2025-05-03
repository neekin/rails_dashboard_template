class AddWebhookUrlToDynamicTables < ActiveRecord::Migration[8.0]
  def change
    add_column :dynamic_tables, :webhook_url, :string
  end
end
