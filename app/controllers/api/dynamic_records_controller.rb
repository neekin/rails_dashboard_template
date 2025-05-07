module Api
  class DynamicRecordsController < AdminController
    before_action :validate_user_ownership!, only: [ :index, :create, :update, :destroy ]
    before_action :authorize_access_request!
    skip_before_action :authorize_access_request!, only: [ :serve_file ]
    def serve_file
      table = DynamicTable.find(params[:dynamic_table_id])
      record_id = params[:id]
      field_name = params[:field_name].to_s.split("/").first

      # 验证字段是否存在且为文件类型
      dynamic_field = table.dynamic_fields.find_by(name: field_name, field_type: "file")
      unless dynamic_field
        render json: { error: "无效的文件字段: #{field_name}" }, status: :not_found
        return
      end

      # 获取记录中的 signed_id
      query = "SELECT #{field_name} FROM dyn_#{table.id} WHERE id = #{record_id}"
      record_data = ActiveRecord::Base.connection.select_one(query)

      unless record_data && record_data[field_name].present?
        render json: { error: "记录 ##{record_id} 没有字段 '#{field_name}' 的文件" }, status: :not_found
        return
      end

      signed_id = record_data[field_name]

      # 查找 Active Storage Blob
      begin
        blob = ActiveStorage::Blob.find_signed!(signed_id)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        render json: { error: "无法找到或验证文件" }, status: :not_found
        return
      end

      # 根据环境和存储服务类型决定服务方式
      begin
        # 检查是否是 S3 兼容服务
        is_s3_service = defined?(ActiveStorage::Service::S3Service) && blob.service.is_a?(ActiveStorage::Service::S3Service)

        # 使用配置项判断是否启用重定向策略，并且当前服务是 S3 兼容的
        if Rails.application.config.x.file_serving_strategy == :redirect && is_s3_service
          # --- 重定向策略 (MinIO/S3): 生成预签名 URL 并重定向 ---
          expires_in = 10.minutes
          disposition_param = params[:disposition] == "attachment" ? :attachment : :inline
          redirect_url = blob.url(expires_in: expires_in, disposition: disposition_param)
          redirect_to redirect_url, allow_other_host: true, status: :found
        else
          # --- 流式传输策略 (Rails send_data): 适用于 Disk 服务或明确配置为 :stream ---
          data = blob.download
          disposition_param = params[:disposition] == "attachment" ? "attachment" : "inline"
          send_data data,
                    filename: blob.filename.to_s,
                    content_type: blob.content_type,
                    disposition: disposition_param
        end
      rescue ActiveStorage::FileNotFoundError
        render json: { error: "文件在存储服务中未找到" }, status: :not_found
      rescue => e
        Rails.logger.error "Error serving file blob #{blob.key}: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: "无法提供文件" }, status: :internal_server_error
      end
    end

    def create
      # table = DynamicTable.find(params[:dynamic_table_id])

      # 动态解析请求参数
      record_params = if request.content_type == "application/json"
        JSON.parse(request.body.read).with_indifferent_access[:record]
      else
        permitted_record_params.to_h
      end
      # record_params = permitted_record_params.to_h # 转换为普通哈希
      # 添加更详细的日志
      Rails.logger.debug "Request content type: #{request.content_type}"
      Rails.logger.debug "Raw parameters: #{params.inspect}"
      Rails.logger.debug "Record params: #{params[:record].inspect}"


      # 处理文件字段
      file_fields = @dynamic_table.dynamic_fields.where(field_type: "file").pluck(:name)
      Rails.logger.debug "File fields from DB: #{file_fields.inspect}"

      file_fields.each do |file_field|
        Rails.logger.debug "Processing file field: #{file_field}"
        if record_params[file_field].present?
          uploaded_file = record_params[file_field]
          Rails.logger.debug "Uploaded file object class: #{uploaded_file.class.name}"
          Rails.logger.debug "Uploaded file details: #{uploaded_file.inspect}"

          # 检查文件对象
          if uploaded_file.is_a?(ActionDispatch::Http::UploadedFile)
            record_params[file_field] = ActiveStorage::Blob.create_and_upload!(
              io: uploaded_file.tempfile,
              filename: uploaded_file.original_filename,
              content_type: uploaded_file.content_type
            ).signed_id
            Rails.logger.debug "File successfully processed and stored with signed_id"
          else
            Rails.logger.error "Invalid file format for field: #{file_field}"
            render json: { error: "Invalid file format for field: #{file_field}" }, status: :unprocessable_entity
            return
          end
        end
      end

      # 获取字段定义
      fields = @dynamic_table.dynamic_fields.select(:name, :field_type).map { |field| [ field.name, field.field_type ] }.to_h

      # 验证必填字段
      required_fields = @dynamic_table.dynamic_fields.where(required: true).pluck(:name)
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
          Rails.logger.error "Field '#{key}' does not exist in table 'dyn_#{@dynamic_table.id}'"
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

      sql = "INSERT INTO dyn_#{@dynamic_table.id} (#{field_names.join(', ')}) VALUES (#{field_values.join(', ')})"
      Rails.logger.info "Executing SQL: #{sql}"

      begin
        result = ActiveRecord::Base.connection.execute(sql)
        head :created
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
        # 检查是否是唯一约束错误
        if e.message.match?(/duplicate entry|unique constraint|violates unique/i)
          field_name = extract_duplicate_field_from_error(e.message)
          error_message = field_name ? "字段 '#{field_name}' 的值已存在，必须唯一" : "记录包含重复值，违反了唯一约束"
          render json: { error: error_message }, status: :unprocessable_entity
        else
          Rails.logger.error "创建记录时出错: #{e.message}"
          render json: { error: "创建记录时出错: #{e.message}" }, status: :internal_server_error
        end
      rescue => e
        Rails.logger.error "创建记录时出错: #{e.message}"
        render json: { error: "创建记录时出错: #{e.message}" }, status: :internal_server_error
      end
    end # 结束 create 方法

    def index
      # table = DynamicTable.find(params[:dynamic_table_id])

      # 获取字段定义
      fields = @dynamic_table.dynamic_fields.select(:name, :field_type, :required).map do |field|
        {
          name: field.name,
          field_type: field.field_type,
          required: field.required
        }
      end

      # 获取查询参数
      query_params = params.permit(:current, :pageSize, :query, :dynamic_table_id).to_h
      current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
      page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

      # 解析过滤条件
      filters = JSON.parse(query_params["query"] || "{}").except("current", "pageSize")
      table_name = "dyn_#{@dynamic_table.id}"

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

      # 获取文件字段列表
      file_fields = @dynamic_table.dynamic_fields.where(field_type: "file").pluck(:name)

      # 处理文件字段，替换 signed_id 为文件 URL
      if file_fields.any?
        data.each do |record|
          file_fields.each do |field|
            signed_id = record[field]
            if signed_id.present?
              begin
                record[field] = dynamic_record_file_url(
                  table_id: @dynamic_table.id,
                  id: record["id"],
                  field_name: field,
                  host: request.host_with_port,
                  signed_id: signed_id
                )
              rescue => e
                Rails.logger.error "Error generating file URL for record #{record["id"]}, field #{field}: #{e.message}"
                record[field] = nil
              end
            else
              record[field] = nil
            end
          end
        end
      end
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
      # table = DynamicTable.find(params[:dynamic_table_id])
      record_id = params[:id]
      record_params = permitted_record_params.to_h # 转换为普通哈希
      # 添加更详细的日志
      Rails.logger.debug "Request content type: #{request.content_type}"
      Rails.logger.debug "Raw parameters: #{params.inspect}"
      Rails.logger.debug "Record params: #{record_params.inspect}"
      # 获取字段定义
      fields = @dynamic_table.dynamic_fields.select(:name, :field_type).map { |field| [ field.name, field.field_type ] }.to_h



    # 处理文件字段
    file_fields = @dynamic_table.dynamic_fields.where(field_type: "file").pluck(:name)
    Rails.logger.debug "File fields from DB: #{file_fields.inspect}"

      file_fields.each do |file_field|
        Rails.logger.debug "Processing file field: #{file_field}"
        # 首先检查参数中是否包含该字段
        if params[:record].key?(file_field)
          # 如果字段存在于提交的参数中
          if record_params[file_field].present?
            uploaded_file = record_params[file_field]
            Rails.logger.debug "Uploaded file object class: #{uploaded_file.class.name}"
            Rails.logger.debug "Uploaded file details: #{uploaded_file.inspect}"

            # 检查文件对象
            if uploaded_file.is_a?(ActionDispatch::Http::UploadedFile)
              # 如果是新上传的文件，处理并保存
              record_params[file_field] = ActiveStorage::Blob.create_and_upload!(
                io: uploaded_file.tempfile,
                filename: uploaded_file.original_filename,
                content_type: uploaded_file.content_type
              ).signed_id
              Rails.logger.debug "File successfully processed and stored with signed_id"
            elsif uploaded_file.is_a?(String) && uploaded_file.match?(/^eyJfcmFpbHMiOnsibWVzc2FnZSI6/)
              # 如果已经是有效的 signed_id，则保留（可能是前端回传的已有文件ID）
              Rails.logger.debug "Field #{file_field} already contains a valid signed_id"
            elsif uploaded_file.is_a?(String) && (uploaded_file.start_with?("http://") || uploaded_file.start_with?("https://") || uploaded_file.start_with?("/"))
              # 如果是URL形式，可能是前端回传的文件URL，忽略此次更新
              Rails.logger.debug "Field #{file_field} contains a URL, keeping original value"
              record_params.delete(file_field)
            else
              Rails.logger.error "Invalid file format for field: #{file_field}, class: #{uploaded_file.class.name}, value: #{uploaded_file.inspect}"
              render json: { error: "文件格式无效：#{file_field}。请上传有效的文件或清空该字段。" }, status: :unprocessable_entity
              return
            end
          elsif record_params[file_field] == "" || record_params[file_field] == nil
            # 用户明确清除了字段内容
            record_params[file_field] = nil
            Rails.logger.debug "Clearing content for file field: #{file_field}"
          end
        else
          # 参数中没有包含此字段，表示用户没有操作该字段，应保持原值
          # 从record_params中移除该字段，防止影响原有值
          record_params.delete(file_field)
          Rails.logger.debug "Field #{file_field} not included in params, keeping original value"
        end
    end
      # 根据字段类型转换参数值
      updates = record_params.map do |key, value|
        field_type = fields[key]
        if field_type.nil?
          Rails.logger.error "Field '#{key}' does not exist in table 'dyn_#{@dynamic_table.id}'"
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

      sql = "UPDATE dyn_#{@dynamic_table.id} SET #{updates}, updated_at = #{ActiveRecord::Base.connection.quote(Time.current)} WHERE id = #{record_id}"
      Rails.logger.info "Executing SQL: #{sql}"

      begin
        # 执行 UPDATE 语句
        ActiveRecord::Base.connection.execute(sql)

        # 如果没有异常抛出，则认为更新成功
        head :ok # 200 OK 表示成功更新

      rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
        # 检查是否是唯一约束错误
        if e.message.match?(/duplicate entry|unique constraint|violates unique/i)
          field_name = extract_duplicate_field_from_error(e.message)
          error_message = field_name ? "字段 '#{field_name}' 的值已存在，必须唯一" : "记录包含重复值，违反了唯一约束"
          render json: { error: error_message }, status: :unprocessable_entity
        else
          Rails.logger.error "创建记录时出错: #{e.message}"
          render json: { error: "创建记录时出错: #{e.message}" }, status: :internal_server_error
        end
      rescue => e
        Rails.logger.error "创建记录时出错: #{e.message}"
        render json: { error: "创建记录时出错: #{e.message}" }, status: :internal_server_error
      end
    end

    def destroy
      # table = DynamicTable.find(params[:dynamic_table_id])
      record_id = params[:id]

      sql = "DELETE FROM dyn_#{@dynamic_table.id} WHERE id = #{record_id}"
      ActiveRecord::Base.connection.execute(sql)
      head :ok
    end

    private

    def extract_duplicate_field_from_error(message)
      # 处理PostgreSQL错误
      if message.match?(/violates unique constraint/i)
        # 提取PostgreSQL的约束名称，通常包含字段名
        match = message.match(/violates unique constraint "([^"]+)"/)
        if match && match[1]
          constraint_name = match[1]
          # 尝试从约束名中提取字段名
          field_match = constraint_name.match(/index_\w+_on_(\w+)/)
          return field_match[1] if field_match && field_match[1]
        end
      end

      # 处理MySQL错误
      if message.match?(/Duplicate entry/i)
        match = message.match(/for key ['\"]([^'\"]+)['\"]/)
        return match[1].gsub(/^index_\w+_on_/, "") if match && match[1]
      end

      # 处理SQLite错误
      if message.match?(/unique constraint failed/i)
        match = message.match(/constraint failed: (\w+)\.(\w+)/)
        return match[2] if match && match[2]
      end

      # 如果无法确定具体字段，返回nil
      nil
    end

    # def extract_duplicate_field_from_error(message)
    #   match = message.match(/key '.*?\.index_.*?_on_(.*?)'/)
    #   match ? match[1] : nil
    # end

    def dynamic_record_file_url(options = {})
      table_id = options[:table_id]
      id = options[:id]
      field_name = options[:field_name]
      # host = options[:host] # 不再需要 host，生成相对路径
      signed_id = options[:signed_id]

      # 基础 URL 指向 Rails 的 serve_file 动作 (相对路径)
      url = "/api/dynamic_tables/#{table_id}/dynamic_records/#{id}/files/#{field_name}"

      # 尝试获取原始文件名并附加到 URL 路径末尾
      if signed_id.present?
        begin
          blob = ActiveStorage::Blob.find_signed(signed_id) # 使用 find_signed 避免抛错
          if blob&.filename.present?
            url += "/#{CGI.escape(blob.filename.to_s)}"
          end
        rescue => e
          Rails.logger.error "Error getting filename for signed_id #{signed_id} in URL generation: #{e.message}"
        end
      end

      url # 返回相对路径
    end
    # 允许的参数
    def permitted_record_params
      params.require(:record).permit!
    end
  end
end
