# app/services/dynamic_table_service.rb
class DynamicTableService
  class << self
    # --- 核心表结构操作 ---

    # 确保物理表存在，如果不存在则创建（包含基础列和时间戳）
    def ensure_table_exists(table)
      table_name = physical_table_name(table)
      unless connection.table_exists?(table_name)
        Rails.logger.info "创建物理表: #{table_name}"
        connection.create_table(table_name) do |t|
          # 可以选择在这里添加一些始终存在的列，如果需要的话
          # t.integer :some_base_column
          t.timestamps
        end
        Rails.logger.info "物理表 #{table_name} 创建成功"
      end
      table_name
    end

    # 添加字段到物理表
    def add_field_to_physical_table(table, field)
      table_name = ensure_table_exists(table) # 确保表存在
      safe_field_name = sanitize_column_name(field.name)
      type_symbol = map_field_type_to_symbol(field.field_type)

      if column_exists?(table_name, safe_field_name)
        Rails.logger.warn "字段 #{safe_field_name} 已存在于表 #{table_name}，跳过添加"
        # 考虑返回一个表示“已存在”的状态，如果控制器需要区分
        return { success: true, status: :already_exists }
      end

      Rails.logger.info "向表 #{table_name} 添加字段: #{safe_field_name} (类型: #{type_symbol}, 必填: #{field.required}, 唯一: #{field.unique})"

      begin
        options = { null: !field.required }
        default_value = determine_default_value(field.field_type) if field.required
        options[:default] = default_value if field.required && !default_value.nil?

        connection.add_column(table_name, safe_field_name, type_symbol, **options)
        Rails.logger.info "字段 #{safe_field_name} 添加成功"

        if field.unique
          # 注意：如果 add_index 失败，下面的 rescue 会捕获
          add_unique_index(table_name, safe_field_name)
        end

        { success: true } # 返回成功状态
      # --- 修改 Rescue 逻辑 ---
      rescue ActiveRecord::RecordNotUnique => e # 添加唯一索引时可能发生
        Rails.logger.error "添加字段 #{safe_field_name} 的唯一索引失败（唯一性冲突）: #{e.message}"
        # 尝试回滚列添加（如果可能且需要）
        # connection.remove_column(table_name, safe_field_name) rescue nil
        { success: false, error: "无法添加唯一约束，因为列 '#{safe_field_name}' 中存在重复值。" }
      rescue ActiveRecord::StatementInvalid => e
        # 捕获添加列或添加索引时的 SQL 错误
        Rails.logger.error "添加字段 #{safe_field_name} 到表 #{table_name} 失败 (StatementInvalid): #{e.message}"
        # 尝试回滚列添加（如果可能且需要）
        # connection.remove_column(table_name, safe_field_name) rescue nil
        # 返回包含具体数据库错误的通用错误信息
        { success: false, error: "添加字段时发生数据库错误: #{e.message}" }
      rescue => e
        Rails.logger.error "添加字段 #{safe_field_name} 到表 #{table_name} 时发生未知错误: #{e.message}\n#{e.backtrace.join("\n")}"
        # 尝试回滚列添加（如果可能且需要）
        # connection.remove_column(table_name, safe_field_name) rescue nil
        { success: false, error: "添加字段时发生未知错误，请联系管理员。" }
        # --- 结束修改 ---
      end
    end

    # 从物理表删除字段
    def remove_field_from_physical_table(table, field)
      table_name = physical_table_name(table)
      safe_field_name = sanitize_column_name(field.name)

      unless column_exists?(table_name, safe_field_name)
        Rails.logger.warn "字段 #{safe_field_name} 不存在于表 #{table_name}，跳过删除"
        return true
      end

      Rails.logger.info "从表 #{table_name} 删除字段: #{safe_field_name} (唯一性: #{field.unique})"

      begin
        # 如果字段有唯一约束，先删除唯一索引
        if field.unique
          remove_unique_index(table_name, safe_field_name)
        end

        # 删除字段
        connection.remove_column(table_name, safe_field_name)
        Rails.logger.info "字段 #{safe_field_name} 删除成功"
        true
      rescue => e
        Rails.logger.error "删除字段 #{safe_field_name} 从表 #{table_name} 失败: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    # 重命名物理表中的字段
    def rename_field_in_physical_table(table, old_name, new_name)
      table_name = physical_table_name(table)
      safe_old_name = sanitize_column_name(old_name)
      safe_new_name = sanitize_column_name(new_name) # 对新名称也进行清理

      # 基础检查
      raise "物理表 #{table_name} 不存在" unless connection.table_exists?(table_name)
      raise "旧字段名 #{safe_old_name} 在表 #{table_name} 中不存在" unless column_exists?(table_name, safe_old_name)
      raise "新字段名 #{safe_new_name} 在表 #{table_name} 中已存在" if column_exists?(table_name, safe_new_name)
      # !! 安全性: 强烈建议在 DynamicField 模型中添加对 new_name 的格式验证 !!
      if safe_new_name.blank? || safe_new_name =~ /[^a-zA-Z0-9_]/ || safe_new_name.length > 60 # 示例长度限制
         raise "无效的新字段名: #{new_name}"
      end


      Rails.logger.info "在表 #{table_name} 中重命名字段: 从 #{safe_old_name} 到 #{safe_new_name}"
      begin
        connection.rename_column(table_name, safe_old_name, safe_new_name)
        Rails.logger.info "字段重命名成功"
        true
      rescue => e
        Rails.logger.error "重命名字段失败: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    # 修改字段类型
    def change_field_type(table, field_name, new_type_string, old_type_string)
      table_name = physical_table_name(table)
      safe_field_name = sanitize_column_name(field_name)
      new_type_symbol = map_field_type_to_symbol(new_type_string)
      # old_type_symbol = map_field_type_to_symbol(old_type_string) # 可能需要旧类型符号

      raise "字段 #{safe_field_name} 在表 #{table_name} 中不存在" unless column_exists?(table_name, safe_field_name)

      Rails.logger.info "修改表 #{table_name} 中字段 #{safe_field_name} 的类型: 从 #{old_type_string} 到 #{new_type_string} (#{new_type_symbol})"

      begin
        if sqlite?
          # SQLite 需要使用临时表策略
          change_field_type_sqlite(table_name, safe_field_name, new_type_symbol)
        else
          # 其他数据库尝试使用 change_column
          # 注意: change_column 可能需要提供所有选项，如 limit, precision, scale, null, default
          # 获取现有列的选项可能比较复杂，这里简化处理，只传递类型
          # 对于更复杂的转换（例如 string -> integer），可能需要 'USING expression'，这超出了 change_column 的标准功能
          connection.change_column(table_name, safe_field_name, new_type_symbol)
          # 可能需要根据 new_type_symbol 调整其他选项，如 nullability
          # field = table.dynamic_fields.find_by(name: field_name)
          # connection.change_column_null(table_name, safe_field_name, !field.required) if field
        end
        Rails.logger.info "字段类型修改成功"
        true
      rescue ActiveRecord::StatementInvalid => e
         # 类型转换失败通常会抛出这个错误
         Rails.logger.error "修改字段类型失败 (可能是数据不兼容): #{e.message}"
         # 可以尝试提供更友好的错误信息
         raise "修改字段类型失败，请检查该列中是否存在与新类型 (#{new_type_string}) 不兼容的数据。"
      rescue => e
        Rails.logger.error "修改字段类型失败: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end

    # 更改字段的唯一约束
    def change_field_unique_constraint(table, field_name, add_unique)
      table_name = physical_table_name(table)
      safe_field_name = sanitize_column_name(field_name)

      # 1. 检查字段是否存在
      unless column_exists?(table_name, safe_field_name)
         return { success: false, error: "字段 '#{safe_field_name}' 在表 '#{table_name}' 中不存在。" }
      end

      action = add_unique ? "添加" : "移除"
      Rails.logger.info "#{action}表 #{table_name} 中字段 #{safe_field_name} 的唯一约束"

      begin
        if add_unique
          # 2. 添加唯一约束
          # 检查是否已存在唯一索引 (避免重复添加)
          unless index_exists?(table_name, safe_field_name, unique: true)
            Rails.logger.info "[Service change_field_unique_constraint] Calling add_unique_index for '#{safe_field_name}'"
            add_unique_index(table_name, safe_field_name)
            Rails.logger.info "[Service change_field_unique_constraint] add_unique_index call completed for '#{safe_field_name}'"
          else
            Rails.logger.warn "字段 #{safe_field_name} 已存在唯一索引，跳过添加"
            # 注意：如果索引已存在，这里直接返回 { success: true }，因为目标状态已达成
          end
        else
          # 3. 移除唯一约束
          # 检查是否存在唯一索引 (避免移除不存在的索引)
          if index_exists?(table_name, safe_field_name, unique: true)
             # 调用 remove_unique_index，它会执行 remove_index
             remove_unique_index(table_name, safe_field_name) # 可能抛出 StatementInvalid
          else
             Rails.logger.warn "字段 #{safe_field_name} 不存在唯一索引，跳过移除"
            # 注意：如果索引本就不存在，这里直接返回 { success: true }，因为目标状态已达成
          end
        end
       # 4. 如果没有异常，或者因为索引已存在/不存在而跳过操作，则到达这里
       Rails.logger.info "[Service change_field_unique_constraint] Reached end of 'begin' block for field '#{safe_field_name}', returning success: true"
        { success: true }
        # 5. 捕获添加索引时的唯一性冲突 (数据重复)
        rescue ActiveRecord::RecordNotUnique => e
          # --- 添加日志 ---
          Rails.logger.error "[Service change_field_unique_constraint] !!! CAUGHT RecordNotUnique !!! for field '#{safe_field_name}': #{e.message}"
          # --- 结束日志 ---
          { success: false, error: "无法添加唯一约束，因为列 '#{safe_field_name}' 中存在重复值。" }
        rescue ActiveRecord::StatementInvalid => e
          # --- 添加日志 ---
          Rails.logger.error "[Service change_field_unique_constraint] !!! CAUGHT StatementInvalid !!! for field '#{safe_field_name}': #{e.message}"
          match_result = e.message.match?(/unique constraint|duplicate key|index.*already exists/i)
          Rails.logger.error "[Service change_field_unique_constraint] Match result for unique constraint pattern: #{match_result}"
          # --- 结束日志 ---
          if add_unique && match_result
            Rails.logger.error "[Service change_field_unique_constraint] StatementInvalid matched unique constraint pattern for field '#{safe_field_name}'"
            { success: false, error: "无法添加唯一约束，因为列 '#{safe_field_name}' 中存在重复值或唯一索引已存在。" }
          else
            Rails.logger.error "[Service change_field_unique_constraint] StatementInvalid did NOT match unique constraint pattern for field '#{safe_field_name}'"
            { success: false, error: "更改唯一约束时发生数据库错误: #{e.message}" }
          end
        rescue => e # 捕获所有其他 StandardError 及其子类
          # --- 添加日志 ---
          Rails.logger.error "[Service change_field_unique_constraint] !!! CAUGHT Generic Error !!! for field '#{safe_field_name}': #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}" # Log first 5 lines of backtrace
          # --- 结束日志 ---
          { success: false, error: "更改字段唯一约束时发生未知错误，请联系管理员。" }
        end
    end




    # 获取动态模型类
    def get_dynamic_model(table)
      table_name = physical_table_name(table)
      raise "物理表 #{table_name} 不存在" unless connection.table_exists?(table_name)

      # 缓存模型类以提高性能，但要注意 schema 变化时需要清除缓存
      @dynamic_models ||= {}
      model_key = table_name.to_sym

      # 如果模型已定义且表结构未变（简化检查：只检查列数），则重用
      # 更可靠的方法是比较列信息摘要或版本号
      # if @dynamic_models[model_key] && @dynamic_models[model_key].columns.size == connection.columns(table_name).size
      #   return @dynamic_models[model_key]
      # end

      # 移除旧的常量定义（如果存在），避免 "already initialized constant" 警告
      class_name = table_name.camelize
      Object.send(:remove_const, class_name) if Object.const_defined?(class_name)

      # 创建新的动态模型类
      model_class = Class.new(ActiveRecord::Base) do
        self.table_name = table_name
        # 可以在这里添加关联、验证等，如果需要的话
        # 例如，处理文件上传 (如果使用 ActiveStorage)
        table.dynamic_fields.where(field_type: "file").each do |file_field|
          sanitized_name = DynamicTableService.sanitize_column_name(file_field.name).to_sym
          has_one_attached sanitized_name
        end
      end

      # 在全局命名空间中定义这个类，以便其他地方可以引用
      Object.const_set(class_name, model_class)

      # 强制重新加载列信息
      model_class.reset_column_information
      @dynamic_models[model_key] = model_class # 缓存新定义的类

      model_class
    end

    # --- 辅助方法 ---

    def physical_table_name(table)
      # 使用更安全的表名，避免潜在冲突，但保持可读性
      # "dyn_#{table.app_entity_id}_#{table.id}" 或使用 UUID
      "dyn_#{table.id}" # 当前实现
    end

    def sanitize_column_name(name)
      # 基础清理，但依赖于模型层的严格验证
      name.to_s.parameterize.underscore.gsub(/[^a-z0-9_]/, "")
    end

    def column_exists?(table_name, column_name)
      connection.column_exists?(table_name, column_name)
    rescue ActiveRecord::StatementInvalid # 处理表不存在的情况
      false
    end

    def index_exists?(table_name, column_name, options = {})
      # 检查 options 是否包含 :name 键，Rails 的 index_exists? 通常需要 index_name
      index_name_option = options[:name]
      unique_option = options[:unique] # 获取 unique 选项
      column_name_str = column_name.to_s

      if sqlite?
        # 对于 SQLite，手动检查索引列表更可靠，因为它对 index_exists? 的参数支持有限
        connection.indexes(table_name).any? do |index|
          # 1. 检查名称（如果提供了名称选项）
          name_match = index_name_option.nil? || index.name == index_name_option.to_s
          # 2. 检查唯一性（如果提供了 unique 选项）
          unique_match = unique_option.nil? || index.unique == unique_option
          # 3. 检查索引是否包含指定的列
          column_match = index.columns.include?(column_name_str)

          # 必须同时满足所有提供的条件
          name_match && unique_match && column_match
        end
      else
        # 对于其他数据库，尝试标准调用，但优先使用 index_name (如果提供)
        if index_name_option
          # 如果提供了索引名，Rails 的 index_exists? 通常期望 (table_name, index_name)
          connection.index_exists?(table_name, index_name_option)
        else
          # 如果没有提供索引名，尝试使用 (table_name, column_name, options)
          # 注意：这仍然可能因适配器而异，但比传递三个参数更标准
          connection.index_exists?(table_name, column_name, **options)
        end
      end
    rescue ActiveRecord::StatementInvalid
      # 如果表不存在等情况，则索引肯定不存在
      false
    end

    def map_field_type_to_symbol(field_type_string)
      case field_type_string.to_s.downcase
      when "string" then :string
      when "integer" then :integer
      when "boolean" then :boolean
      when "text" then :text
      when "date" then :date
      when "datetime" then :datetime
      when "decimal" then :decimal # 可能需要 precision/scale
      when "float" then :float
      when "file" then :string # 文件字段通常存储 blob_id 或路径字符串
      else
        Rails.logger.warn "未知的字段类型: #{field_type_string}，使用默认类型 :string"
        :string # 或者 :text
      end
    end

    def determine_default_value(field_type_string)
      case field_type_string.to_s.downcase
      when "string", "text", "file" then "" # 文件字段默认空字符串或nil
      when "integer" then 0
      when "boolean" then false
      when "date" then Date.today # 或 nil
      when "datetime" then Time.current # 或 nil
      when "decimal", "float" then 0.0
      else nil
      end
    end

    def connection
      ActiveRecord::Base.connection
    end

    def sqlite?
      connection.adapter_name.casecmp("sqlite").zero?
    end


    # --- SQLite 特定操作 ---

    # SQLite 修改字段类型的临时表策略
    def change_field_type_sqlite(table_name, field_name, new_type_symbol)
      temp_table_name = "#{table_name}_temp_#{SecureRandom.hex(4)}"
      Rails.logger.info "[SQLite] 使用临时表 #{temp_table_name} 修改字段 #{field_name} 类型为 #{new_type_symbol}"

      begin
        connection.transaction do
          # 1. 获取旧表结构 (包括主键、索引等)
          columns_info = connection.columns(table_name)
          indexes_info = connection.indexes(table_name)
          # PRAGMA table_info 更详细，但 columns 通常够用

          # 2. 构建新表结构定义
          new_columns_sql = columns_info.map do |col|
            col_name = connection.quote_column_name(col.name)
            col_type = col.name == field_name ? connection.type_to_sql(new_type_symbol) : col.sql_type
            col_null = col.null ? "" : "NOT NULL"
            col_default = col.default.nil? ? "" : "DEFAULT #{connection.quote(col.default)}"
            col_pk = col.primary_key? ? "PRIMARY KEY" : ""
            # 注意: SQLite 的 AUTOINCREMENT 需要 INTEGER PRIMARY KEY
            if col.primary_key? && col.type == :integer && col.sql_type.match?(/integer/i)
               col_pk = "PRIMARY KEY AUTOINCREMENT"
               col_type = "INTEGER" # 强制为 INTEGER
            end
            "#{col_name} #{col_type} #{col_pk} #{col_null} #{col_default}".squish
          end.join(", ")

          # 3. 创建临时表
          connection.execute("CREATE TABLE #{connection.quote_table_name(temp_table_name)} (#{new_columns_sql})")
          Rails.logger.debug "[SQLite] 临时表 #{temp_table_name} 创建成功"

          # 4. 复制数据 (注意类型转换可能在此处失败)
          column_names = columns_info.map { |c| connection.quote_column_name(c.name) }.join(", ")
          # !! 这里需要小心，如果新旧类型不兼容，INSERT SELECT 会失败 !!
          # 可能需要显式 CAST: SELECT CAST(col1 AS new_type), col2 FROM old_table
          # 为了简化，假设大部分转换 SQLite 能自动处理或在 change_column 时已验证
          connection.execute("INSERT INTO #{connection.quote_table_name(temp_table_name)} (#{column_names}) SELECT #{column_names} FROM #{connection.quote_table_name(table_name)}")
          Rails.logger.debug "[SQLite] 数据已复制到 #{temp_table_name}"

          # 5. 复制索引 (不包括主键索引)
          indexes_info.each do |index|
             next if index.name.match?(/sqlite_autoindex/) # 跳过主键/内部索引
             index_cols = index.columns.map { |c| connection.quote_column_name(c) }.join(", ")
             unique_clause = index.unique ? "UNIQUE" : ""
             index_name_quoted = connection.quote_table_name(index.name.gsub(table_name, temp_table_name)) # 尝试重命名索引
             temp_table_name_quoted = connection.quote_table_name(temp_table_name)
             connection.execute("CREATE #{unique_clause} INDEX #{index_name_quoted} ON #{temp_table_name_quoted} (#{index_cols})")
          end
           Rails.logger.debug "[SQLite] 索引已复制到 #{temp_table_name}"


          # 6. 删除旧表
          connection.execute("DROP TABLE #{connection.quote_table_name(table_name)}")
          Rails.logger.debug "[SQLite] 旧表 #{table_name} 已删除"

          # 7. 重命名临时表
          connection.execute("ALTER TABLE #{connection.quote_table_name(temp_table_name)} RENAME TO #{connection.quote_table_name(table_name)}")
          Rails.logger.info "[SQLite] 临时表 #{temp_table_name} 已重命名为 #{table_name}"
        end # end transaction
      rescue => e
        Rails.logger.error "[SQLite] 修改字段类型失败，尝试回滚: #{e.message}"
        # 尝试清理临时表（如果事务失败可能不会自动清理）
        connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(temp_table_name)}") rescue nil
        raise e # 重新抛出原始错误
      end
    end

    # --- 索引辅助方法 ---
    def add_unique_index(table_name, column_name)
      index_name = generate_index_name(table_name, column_name)
      Rails.logger.info "为字段 #{column_name} 添加唯一索引 #{index_name}"

      # 检查是否有重复数据
      duplicate_check_sql = "SELECT COUNT(*) as count FROM (SELECT #{column_name} FROM #{table_name} GROUP BY #{column_name} HAVING COUNT(*) > 1 AND #{column_name} IS NOT NULL) as duplicates"
      duplicates = connection.select_one(duplicate_check_sql)

      if duplicates && duplicates["count"].to_i > 0
        return { success: false, error: "无法添加唯一约束，因为列 '#{column_name}' 中存在重复值。" }
      end

      # 添加唯一索引
      connection.add_index(table_name, column_name, unique: true, name: index_name)
      { success: true }
    rescue ActiveRecord::RecordNotUnique => e
      { success: false, error: "无法添加唯一约束，因为列 '#{column_name}' 中存在重复值。" }
    rescue => e
      { success: false, error: "添加唯一索引失败: #{e.message}" }
   end

   def remove_unique_index(table_name, column_name)
      index_name = generate_index_name(table_name, column_name)
      # remove_index 需要确切的名称或列名
      # 优先尝试按名称移除
      if index_exists?(table_name, column_name, name: index_name, unique: true)
        Rails.logger.info "删除字段 #{column_name} 的唯一索引 #{index_name}"
        # 这个调用会直接操作数据库，如果失败会抛出异常
        connection.remove_index(table_name, name: index_name)
        { success: true }
      # 如果按名称找不到，尝试按列名移除 (作为备选，可能不精确)
      elsif index_exists?(table_name, column_name, unique: true)
         Rails.logger.warn "未找到名为 #{index_name} 的唯一索引，尝试按列 #{column_name} 删除唯一索引"
         # 这个调用也可能失败
         connection.remove_index(table_name, column: column_name)
         { success: true }
      else
         # 如果两种方式都找不到，记录警告，但不抛异常
         Rails.logger.warn "未找到字段 #{column_name} 的唯一索引（名称: #{index_name}），跳过删除"
         # 如果索引不存在，也算成功
         { success: true }
      end
   rescue => e
      Rails.logger.error "删除唯一索引失败: #{e.message}"
      { success: false, error: "删除唯一索引失败: #{e.message}" }
   end

  def generate_index_name(table_name, column_name)
      # 遵循 Rails 默认索引命名约定 index_table_name_on_column_name
      "index_#{table_name}_on_#{column_name}"
  end
  end
end
