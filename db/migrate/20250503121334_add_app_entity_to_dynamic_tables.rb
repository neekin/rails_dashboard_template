class AddAppEntityToDynamicTables < ActiveRecord::Migration[8.0]
  def up
    # 检查dynamic_tables表是否已有app_entity_id列
    unless column_exists?(:dynamic_tables, :app_entity_id)
      # 添加app_entity_id列
      add_column :dynamic_tables, :app_entity_id, :integer

      # 确保有默认应用
      unless (default_entity_id = get_default_entity_id)
        # 创建默认应用并获取ID
        default_entity_id = create_default_entity
      end

      # 为所有已存在的dynamic_tables记录设置默认app_entity
      if table_exists?(:dynamic_tables) &&
         ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM dynamic_tables").first.first > 0
        execute("UPDATE dynamic_tables SET app_entity_id = #{default_entity_id}")
      end

      # 添加非空约束
      change_column_null :dynamic_tables, :app_entity_id, false

      # 添加外键约束
      add_foreign_key :dynamic_tables, :app_entities

      # 添加索引
      add_index :dynamic_tables, :app_entity_id
    end
  end

  def down
    if column_exists?(:dynamic_tables, :app_entity_id)
      # 先移除外键和索引
      remove_foreign_key :dynamic_tables, :app_entities if foreign_key_exists?(:dynamic_tables, :app_entities)
      remove_index :dynamic_tables, :app_entity_id if index_exists?(:dynamic_tables, :app_entity_id)

      # 移除列
      remove_column :dynamic_tables, :app_entity_id
    end
  end

  private

  def get_default_entity_id
    # 查找默认应用ID
    result = execute("SELECT id FROM app_entities WHERE name = '默认应用' LIMIT 1")
    if result.present? && result.any?
      # 根据不同数据库返回结果类型处理
      if result.first.is_a?(Hash)
        result.first['id']
      else
        result.first.first
      end
    else
      nil
    end
  end

  def create_default_entity
    # 插入默认应用
    execute(<<-SQL)
      INSERT INTO app_entities (name, description, status, created_at, updated_at)
      VALUES ('默认应用', '系统自动创建的默认应用', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL

    # 获取刚创建的应用ID (适配不同数据库)
    case ActiveRecord::Base.connection.adapter_name
    when 'SQLite'
      execute("SELECT last_insert_rowid()").first.first
    when 'Mysql2'
      execute("SELECT LAST_INSERT_ID()").first.first
    when 'PostgreSQL'
      execute("SELECT lastval()").first.first
    else
      # 如果无法直接获取ID，再次查询
      execute("SELECT id FROM app_entities WHERE name = '默认应用' LIMIT 1").first.first
    end
  end
end
