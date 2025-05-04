class AddStatusAndRemarkToApiKeys < ActiveRecord::Migration[8.0]
  def change
    add_column :api_keys, :active, :boolean
    add_column :api_keys, :remark, :string
    # 为active字段添加索引，以优化查询性能
    add_index :api_keys, :active
  end
end
