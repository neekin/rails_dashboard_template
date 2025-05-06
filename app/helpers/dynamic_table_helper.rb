module DynamicTableHelper
  def physical_table_name(table)
    "dyn_#{table.id}"
  end

  # Sanitizes a column name by removing invalid characters
  def sanitize_column_name(column_name)
    column_name.to_s.strip.gsub(/[^a-zA-Z0-9_]/, "_").downcase
  end

  # Maps a field type to an SQL column type
  def sql_column_type(field_type)
    case field_type.to_s
    when "string"
      "VARCHAR(255)"
    when "integer"
      "INTEGER"
    when "boolean"
      "BOOLEAN"
    when "datetime"
      "DATETIME"
    when "date" # 添加对 "date" 类型的支持
      "DATE"
    when "decimal" # 添加对 "decimal" 类型的支持
      "DECIMAL(10,2)"
    when "float" # 添加对 "float" 类型的支持
      "FLOAT"
    else
      "TEXT"
    end
  end

  # Determines the default value for a given field type
  def determine_default_value(field_type, default_value = nil)
    case field_type.to_s
    when "integer"
      default_value.to_i
    when "boolean"
      [ true, "true", 1 ].include?(default_value)
    when "datetime"
      begin
        default_value.is_a?(Time) ? default_value : DateTime.parse(default_value.to_s).to_time
      rescue ArgumentError
        nil
      end
    when "date" # 添加对 "date" 类型的默认值处理
      begin
        Date.parse(default_value.to_s)
      rescue ArgumentError
        nil
      end
    when "decimal", "float" # 添加对 "float" 类型的默认值处理
      default_value.to_f
    when "string", "text"
      default_value.nil? ? "" : default_value.to_s.dup.force_encoding("UTF-8")
    else
      # 对于未知类型，返回 nil
      nil
    end
  end
end
