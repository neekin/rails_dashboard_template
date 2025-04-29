module Api
  class DynamicRecordsController < ApiController
    def create
      table = DynamicTable.find(params[:dynamic_table_id])
      record_params = permitted_record_params.to_h # 转换为普通哈希

      # 获取字段定义
      fields = table.dynamic_fields.select(:name, :field_type).map { |field| [ field.name, field.field_type ] }.to_h

      # 验证必填字段
      required_fields = table.dynamic_fields.where(required: true).pluck(:name)
      missing_fields = required_fields - record_params.keys

      if missing_fields.any?
        render json: { error: "Missing required fields: #{missing_fields.join(', ')}" }, status: :unprocessable_entity
        return
      end

      # 根据字段类型转换参数值
      field_names = []
      field_values = []

      record_params.each do |key, value|
        field_type = fields[key]
        if field_type.nil?
          Rails.logger.error "Field '#{key}' does not exist in table 'dyn_#{table.id}'"
          next
        end

        converted_value = case field_type
        when "integer"
                            value.to_i
        when "decimal", "float"
                            value.to_f
        when "boolean"
                            ActiveRecord::Type::Boolean.new.cast(value)
        else
                            value
        end

        field_names << key
        field_values << ActiveRecord::Base.connection.quote(converted_value)
      end

      if field_names.empty?
        render json: { error: "No valid fields to create" }, status: :unprocessable_entity
        return
      end

      # 添加created_at和updated_at
      current_time = Time.current
      field_names << "created_at"
      field_names << "updated_at"
      field_values << ActiveRecord::Base.connection.quote(current_time)
      field_values << ActiveRecord::Base.connection.quote(current_time)

      sql = "INSERT INTO dyn_#{table.id} (#{field_names.join(', ')}) VALUES (#{field_values.join(', ')})"
      Rails.logger.info "Executing SQL: #{sql}"

      begin
        result = ActiveRecord::Base.connection.execute(sql)
        if result
          # 获取最新插入记录的ID
          last_id_sql = "SELECT last_insert_rowid() as id"
          last_id = ActiveRecord::Base.connection.select_one(last_id_sql)["id"]

          # 返回新创建的记录
          query = "SELECT * FROM dyn_#{table.id} WHERE id = #{last_id}"
          new_record = ActiveRecord::Base.connection.select_one(query)

          render json: { record: new_record }, status: :created
        else
          render json: { error: "Failed to create record" }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "SQL Execution Error: #{e.message}"
        render json: { error: e.message }, status: :internal_server_error
      end
    end

    def index
      table = DynamicTable.find(params[:dynamic_table_id])

      # 获取字段定义
      fields = table.dynamic_fields.select(:name, :field_type, :required).map do |field|
        {
          name: field.name,
          field_type: field.field_type,
          required: field.required
        }
      end

      # 获取查询参数
      query_params = params.permit(:current, :pageSize, :query).to_h
      current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
      page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

      # 解析过滤条件
      filters = JSON.parse(query_params["query"] || "{}").except("current", "pageSize")
      table_name = "dyn_#{table.id}"

      # 构建查询
      query = "SELECT * FROM #{table_name}"
      where_clauses = filters.map do |key, value|
        "#{key} LIKE #{ActiveRecord::Base.connection.quote("%#{value}%")}"
      end
      query += " WHERE #{where_clauses.join(' AND ')}" if where_clauses.any?
      query += " ORDER BY id ASC"
      query += " LIMIT #{page_size} OFFSET #{(current_page - 1) * page_size}"

      # 执行查询
      data = ActiveRecord::Base.connection.select_all(query).to_a

      # 获取总记录数
      total_count_query = "SELECT COUNT(*) AS count FROM #{table_name}"
      total_count_query += " WHERE #{where_clauses.join(' AND ')}" if where_clauses.any?
      total_count = ActiveRecord::Base.connection.select_one(total_count_query)["count"]

      render json: {
        fields: fields,
        data: data,
        pagination: {
          current: current_page,
          pageSize: page_size,
          total: total_count
        }
      }
    end

    def update
      table = DynamicTable.find(params[:dynamic_table_id])
      record_id = params[:id]
      record_params = permitted_record_params.to_h # 转换为普通哈希

      # 获取字段定义
      fields = table.dynamic_fields.select(:name, :field_type).map { |field| [ field.name, field.field_type ] }.to_h

      # 根据字段类型转换参数值
      updates = record_params.map do |key, value|
        field_type = fields[key]
        if field_type.nil?
          Rails.logger.error "Field '#{key}' does not exist in table 'dyn_#{table.id}'"
          next
        end

        converted_value = case field_type
        when "integer"
                            value.to_i
        when "decimal", "float"
                            value.to_f
        when "boolean"
                            ActiveRecord::Type::Boolean.new.cast(value)
        else
                            value
        end
        "#{key} = #{ActiveRecord::Base.connection.quote(converted_value)}"
      end.compact.join(", ")

      if updates.blank?
        render json: { error: "No valid fields to update" }, status: :unprocessable_entity
        return
      end

      sql = "UPDATE dyn_#{table.id} SET #{updates}, updated_at = #{ActiveRecord::Base.connection.quote(Time.current)} WHERE id = #{record_id}"
      Rails.logger.info "Executing SQL: #{sql}"

      begin
        result = ActiveRecord::Base.connection.execute(sql)
        if result
          head :ok
        else
          render json: { error: "Failed to update record" }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "SQL Execution Error: #{e.message}"
        render json: { error: e.message }, status: :internal_server_error
      end
    end

    def destroy
      table = DynamicTable.find(params[:dynamic_table_id])
      record_id = params[:id]

      sql = "DELETE FROM dyn_#{table.id} WHERE id = #{record_id}"
      ActiveRecord::Base.connection.execute(sql)
      head :ok
    end

    private

    # 允许的参数
    def permitted_record_params
      params.require(:record).permit!
    end
  end
end
