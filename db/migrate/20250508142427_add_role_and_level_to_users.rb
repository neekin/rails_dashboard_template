class AddRoleAndLevelToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :role, :integer, default: 0, null: false # 例如: 0 for user, 1 for admin
    add_column :users, :level, :integer, default: 0, null: false # 例如: 0 for free, 1 for premium, etc.
  end
end
