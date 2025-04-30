# app/services/dynamic_table_service.rb
class DynamicTableService
  class << self
    # 创建物理表
    def create_physical_table(table)
      table_name = physical_table_name(table)
      return if ActiveRecord::Base.connection.table_exists?(table_name)

      Rails.logger.info "创建物理表: #{table_name}"
      ActiveRecord::Base.connection.create_table(table_name) do |t|
        table.dynamic_fields.each do |field|
          add_column_to_table_definition(t, field)
        end
        t.timestamps
      end
    end

    # 确保物理表存在
    def ensure_table_exists(table)
      table_name = physical_table_name(table)
      unless ActiveRecord::Base.connection.table_exists?(table_name)
        Rails.logger.info "创建物理表: #{table_name}"
        ActiveRecord::Base.connection.create_table(table_name) do |t|
          t.timestamps
        end
      end
      table_name
    end

    # 添加字段到物理表
    def add_field_to_physical_table(table, field)
      table_name = physical_table_name(table)
      safe_field_name = sanitize_column_name(field.name)

      begin
        # 检查字段是否已存在
        if column_exists?(table_name, safe_field_name)
          Rails.logger.warn "字段 #{safe_field_name} 已存在于表 #{table_name}，跳过创建"
          return
        end

        # 构建添加列的SQL
        sql_type = sql_column_type(field.field_type)
        null_constraint = field.required ? "NOT NULL" : ""

        Rails.logger.info "添加字段: #{safe_field_name} (#{sql_type}) 到表 #{table_name}"
        add_column_sql = "ALTER TABLE #{table_name} ADD COLUMN #{safe_field_name} #{sql_type} #{null_constraint}"
        ActiveRecord::Base.connection.execute(add_column_sql)

        # 如果是必填字段，为现有数据设置默认值
        if field.required
          default_value = determine_default_value(field.field_type)
          Rails.logger.info "为字段 #{safe_field_name} 设置默认值: #{default_value}"
          update_sql = "UPDATE #{table_name} SET #{safe_field_name} = #{ActiveRecord::Base.connection.quote(default_value)}"
          ActiveRecord::Base.connection.execute(update_sql)
        end
        true
      rescue => e
        Rails.logger.error "添加字段失败: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    # 从物理表删除字段
    def remove_field_from_physical_table(table, field)
      table_name = physical_table_name(table)
      safe_field_name = sanitize_column_name(field.name)

      begin
        if column_exists?(table_name, safe_field_name)
          Rails.logger.info "删除字段: #{safe_field_name} 从表 #{table_name}"
          ActiveRecord::Base.connection.execute("ALTER TABLE #{table_name} DROP COLUMN #{safe_field_name}")
        else
          Rails.logger.warn "字段 #{safe_field_name} 在表 #{table_name} 中不存在，跳过删除操作"
        end
        true
      rescue => e
        Rails.logger.error "删除字段失败: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    # 重命名物理表中的字段
    def rename_field_in_physical_table(table, old_name, new_name)
      table_name = "dyn_#{table.id}"

      # 检查表是否存在
      unless ActiveRecord::Base.connection.table_exists?(table_name)
        raise "物理表 #{table_name} 不存在"
      end

      # 检查字段是否存在
      unless ActiveRecord::Base.connection.column_exists?(table_name, old_name)
        raise "字段 #{old_name} 在表 #{table_name} 中不存在"
      end

      # 检查新名称是否已存在
      if ActiveRecord::Base.connection.column_exists?(table_name, new_name)
        raise "字段 #{new_name} 在表 #{table_name} 中已存在"
      end

      # 执行重命名操作
      ActiveRecord::Base.connection.rename_column(table_name, old_name, new_name)
      Rails.logger.info "成功将表 #{table_name} 中的字段 #{old_name} 重命名为 #{new_name}"
    end

    # 更改字段类型
    def change_field_type(table, field_name, new_type, old_type)
      table_name = physical_table_name(table)
      safe_field_name = sanitize_column_name(field_name)

      # 由于SQLite不直接支持ALTER COLUMN TYPE，需要创建临时表并迁移数据
      Rails.logger.info "修改字段类型: #{safe_field_name} 从 #{old_type} 到 #{new_type} 在表 #{table_name}"

      begin
        # 获取表的所有列
        columns_info = ActiveRecord::Base.connection.columns(table_name)
        column_names = columns_info.map(&:name)

        # 创建临时表
        temp_table = "temp_#{table_name}"
        create_temp_table_sql = "CREATE TABLE #{temp_table} AS SELECT * FROM #{table_name} WHERE 0"
        ActiveRecord::Base.connection.execute(create_temp_table_sql)

        # 在临时表中创建所有列，但用新类型替换要修改的列
        columns_info.each do |col|
          col_name = col.name
          col_type = (col_name == safe_field_name) ? sql_column_type(new_type) : col.sql_type
          null_constraint = col.null ? "" : "NOT NULL"

          # 跳过已经存在的列（如主键）
          next if ActiveRecord::Base.connection.column_exists?(temp_table, col_name)

          add_col_sql = "ALTER TABLE #{temp_table} ADD COLUMN #{col_name} #{col_type} #{null_constraint}"
          ActiveRecord::Base.connection.execute(add_col_sql)
        end

        # 复制数据
        columns_str = column_names.join(", ")
        copy_data_sql = "INSERT INTO #{temp_table} (#{columns_str}) SELECT #{columns_str} FROM #{table_name}"
        ActiveRecord::Base.connection.execute(copy_data_sql)

        # 删除原表并重命名临时表
        ActiveRecord::Base.connection.execute("DROP TABLE #{table_name}")
        ActiveRecord::Base.connection.execute("ALTER TABLE #{temp_table} RENAME TO #{table_name}")
        true
      rescue => e
        Rails.logger.error "修改字段类型失败: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    # 辅助方法
    def physical_table_name(table)
      "dyn_#{table.id}"
    end

    def column_exists?(table_name, column_name)
      ActiveRecord::Base.connection.column_exists?(table_name, column_name)
    end

    def sanitize_column_name(name)
      # 移除或替换不安全的字符
      name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
    end

    def sql_column_type(field_type)
      case field_type.to_s.downcase
      when "string"
        "VARCHAR(255)"
      when "integer"
        "INTEGER"
      when "boolean"
        "BOOLEAN"
      when "text"
        "TEXT"
      when "date"
        "DATE"
      when "datetime"
        "DATETIME"
      when "decimal"
        "DECIMAL(10,2)"
      when "float"
        "FLOAT"
      else
        Rails.logger.warn "未知的字段类型: #{field_type}，使用默认类型 TEXT"
        "TEXT"
      end
    end

    def determine_default_value(field_type)
      case field_type.to_s.downcase
      when "string"
        "默认值"
      when "integer"
        0
      when "boolean"
        false
      when "text"
        "默认文本"
      when "date"
        Date.today
      when "datetime"
        Time.current
      when "decimal", "float"
        0.0
      else
        nil
      end
    end

    def get_dynamic_model(table)
      table_name = physical_table_name(table)

      # 检查表是否存在
      unless ActiveRecord::Base.connection.table_exists?(table_name)
        raise "物理表 #{table_name} 不存在"
      end

      # 创建动态模型类
      Class.new(ActiveRecord::Base) do
        self.table_name = table_name
        # 禁用STI
        self.inheritance_column = :_type_disabled
      end
    end

    private

    def add_column_to_table_definition(table_definition, field)
      field_type = field.field_type.to_sym
      null_option = !field.required
      table_definition.send(field_type, field.name, null: null_option)
    end
  end
end
