class AddUserToAppEntities < ActiveRecord::Migration[8.0]
  def up
    # 添加user_id列
    unless column_exists?(:app_entities, :user_id)
      add_column :app_entities, :user_id, :integer

      # 如果已经有app_entities记录，创建默认用户并关联
      if table_exists?(:app_entities) && has_records?(:app_entities)
        # 检查是否已有用户
        user_exists = table_exists?(:users) && has_records?(:users)

        if user_exists
          # 获取第一个用户的ID作为默认值
          default_user_id = get_first_user_id
        else
          # 创建系统管理员用户
          default_user_id = create_admin_user
        end

        # 更新现有记录关联到默认用户
        execute("UPDATE app_entities SET user_id = #{default_user_id}")
      end

      # 添加非空约束
      change_column_null :app_entities, :user_id, false

      # 添加外键约束
      add_foreign_key :app_entities, :users

      # 添加索引
      add_index :app_entities, :user_id
    end
  end

  def down
    if column_exists?(:app_entities, :user_id)
      # 移除外键和索引
      remove_foreign_key :app_entities, :users if foreign_key_exists?(:app_entities, :users)
      remove_index :app_entities, :user_id if index_exists?(:app_entities, :user_id)

      # 移除列
      remove_column :app_entities, :user_id
    end
  end

  private

  # 检查表是否有记录
  def has_records?(table_name)
    result = execute("SELECT COUNT(*) FROM #{table_name}")
    count = nil

    # 处理不同数据库返回的格式
    if result.first.is_a?(Hash)
      # PostgreSQL返回结果如 [{"count"=>5}]
      count = result.first.values.first.to_i
    else
      # SQLite返回结果如 [[5]]
      count = result.first.first.to_i
    end

    count > 0
  end

  # 获取第一个用户ID
  def get_first_user_id
    result = execute("SELECT id FROM users ORDER BY id LIMIT 1")

    if result.first.is_a?(Hash)
      result.first['id']
    else
      result.first.first
    end
  end

  # 创建管理员用户
  def create_admin_user
    require 'bcrypt'
    default_password = BCrypt::Password.create('admin123')

    execute(<<-SQL)
      INSERT INTO users (username, email, password_digest, created_at, updated_at)
      VALUES ('admin', 'admin@example.com', '#{default_password}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL

    # 获取新创建用户的ID
    case ActiveRecord::Base.connection.adapter_name
    when 'SQLite'
      execute("SELECT last_insert_rowid()").first.first
    when 'Mysql2'
      execute("SELECT LAST_INSERT_ID()").first.first
    when 'PostgreSQL'
      execute("SELECT lastval()").first.first
    else
      execute("SELECT id FROM users WHERE username = 'admin' LIMIT 1").first.first
    end
  end
end
