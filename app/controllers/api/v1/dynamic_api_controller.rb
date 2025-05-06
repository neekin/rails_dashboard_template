module Api
  module V1
    class DynamicApiController < ApiController
      before_action :authorize_app_entity!
      # include Rails.application.routes.url_helpers

      before_action :find_table_by_identifier
      before_action :find_record, only: [ :show, :update, :destroy ]
      # 跳过 `authorize_app_entity!` 和 `find_table_by_identifier` 对 `serve_file` 方法的拦截
      # skip_before_action :authorize_app_entity!, only: [ :serve_file ]
      # skip_before_action :find_table_by_identifier, only: [ :serve_file ]
      def trigger_webhook(event, payload)
        webhook_url = @table.webhook_url # 假设每个 AppEntity 都有一个 webhook_url 字段
        return unless webhook_url.present?

        # 将实际的 webhook 调用移至后台作业
        WebhookJob.perform_later(webhook_url, event, payload.as_json) # 使用 as_json 确保 payload 是可序列化的
        Rails.logger.info "Webhook job enqueued for event '#{event}' to '#{webhook_url}'"
      rescue StandardError => e
        Rails.logger.error "Error enqueuing webhook job for event '#{event}': #{e.message}"
      end

      def serve_file
        app_id = params[:appId] # 从 URL 参数中获取 appId
        identifier = params[:identifier] # 从 URL 参数中获取表格标识符
        field_name = params[:field_name] # 从 URL 参数中获取字段名称

        # 验证 appId 是否有效
        @app_entity = AppEntity.find_by(id: app_id)
        unless @app_entity
          render json: { error: "无效的应用 ID: #{app_id}" }, status: :not_found
          return
        end

        # 查找表格
        @table = DynamicTable.find_by(api_identifier: identifier, app_entity_id: @app_entity.id) ||
                 DynamicTable.find_by(id: identifier, app_entity_id: @app_entity.id)

        unless @table
          render json: { error: "找不到表格: #{identifier}" }, status: :not_found
          return
        end

        # 验证字段是否存在且为文件类型
        dynamic_field = @table.dynamic_fields.find_by(name: field_name, field_type: "file")
        unless dynamic_field
          render json: { error: "无效的文件字段: #{field_name}" }, status: :not_found
          return
        end

        # 获取存储在记录中的 signed_id
        @record = DynamicTableService.get_dynamic_model(@table).find_by(id: params[:id])
        unless @record
          render json: { error: "找不到记录 ##{params[:id]}" }, status: :not_found
          return
        end

        signed_id = @record.send(field_name)
        unless signed_id.present?
          render json: { error: "记录 ##{params[:id]} 没有字段 '#{field_name}' 的文件" }, status: :not_found
          return
        end

        # 查找 Active Storage Blob
        begin
          blob = ActiveStorage::Blob.find_signed(signed_id)
          # 配置头信息
          response.headers["Content-Type"] = blob.content_type
          response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
            disposition: params[:disposition] || "inline",
            filename: blob.filename.to_s
          )

          # 对于不同存储服务的处理
          if Rails.application.config.active_storage.service == :local
            # 本地存储
            path = ActiveStorage::Blob.service.send(:path_for, blob.key)
            send_file path, disposition: params[:disposition] || "inline"
          else
            # 远程存储(S3, GCS等)
            redirect_to blob.service_url(disposition: params[:disposition])
          end
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
          render json: { error: "无效或过期的文件引用" }, status: :not_found
          nil
        rescue ActiveStorage::FileNotFoundError
          render json: { error: "找不到文件" }, status: :not_found
        rescue => e
          Rails.logger.error "serve_file错误: #{e.message}\n#{e.backtrace.join("\n")}"
          render json: { error: "处理文件时出错: #{e.message}" }, status: :internal_server_error
        end
      end

      # 处理文件字段
      def handle_file_fields(record, file_params_hash)
        return unless file_params_hash && file_params_hash.keys.any?

        file_params_hash.each do |field_name, file_param|
          if file_param.blank? && record.respond_to?(field_name) && record.send(field_name).present?
            # 如果参数为空但记录中有文件，则删除文件
            begin
              if DynamicTableService.postgresql?
                # PostgreSQL需要引用字段名
                ActiveRecord::Base.connection.execute(
                  "UPDATE dyn_#{@table.id} SET #{DynamicTableService.quote_identifier(field_name)} = NULL WHERE id = #{record.id}"
                )
              else
                # MySQL和SQLite
                ActiveRecord::Base.connection.execute(
                  "UPDATE dyn_#{@table.id} SET #{field_name} = NULL WHERE id = #{record.id}"
                )
              end
            rescue => e
              Rails.logger.error "清除文件字段失败: #{e.message}"
            end
          elsif file_param.present?
            # 如果有新文件，保存并更新记录
            begin
              # 处理文件上传...
              blob = ActiveStorage::Blob.create_and_upload!(
                io: file_param.open,
                filename: file_param.original_filename,
                content_type: file_param.content_type
              )

              # 保存文件的signed_id到数据库字段
              signed_id = blob.signed_id

              if DynamicTableService.postgresql?
                # PostgreSQL需要引用字段名
                ActiveRecord::Base.connection.execute(
                  "UPDATE dyn_#{@table.id} SET #{DynamicTableService.quote_identifier(field_name)} = '#{signed_id}' WHERE id = #{record.id}"
                )
              else
                # MySQL和SQLite
                ActiveRecord::Base.connection.execute(
                  "UPDATE dyn_#{@table.id} SET #{field_name} = '#{signed_id}' WHERE id = #{record.id}"
                )
              end
            rescue => e
              Rails.logger.error "上传文件失败: #{e.message}"
              raise e
            end
          end
        end
      end
      # GET /api/v1/:identifier

      def index
        # 获取查询参数
        query_params = params.permit(:current, :pageSize, :query, :sortField, :sortOrder).to_h
        current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
        page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

        # 获取文件字段名称列表
        file_field_names = @table.dynamic_fields.where(field_type: "file").pluck(:name)

        # 创建连接到物理表的模型
        model_class = DynamicTableService.get_dynamic_model(@table)

        # 构建基础查询，限制表格属于当前授权的 AppEntity
        query = model_class.all

        # 处理过滤条件
        filters = {}
        begin
          filters = JSON.parse(query_params["query"] || "{}").except("current", "pageSize") if query_params["query"].present?
        rescue JSON::ParserError
          # 处理无效JSON
        end

        # 动态构建查询条件
        filters.each do |key, value|
          column_names = model_class.column_names
          if column_names.include?(key.to_s) && value.present?
            query = query.where("#{key} LIKE ?", "%#{value}%")
          end
        end

        # 处理排序
        sort_field = query_params["sortField"].presence || "created_at"
        sort_order = query_params["sortOrder"] == "asc" ? "ASC" : "DESC"

        # 确保排序字段是有效的列
        valid_sort_fields = model_class.column_names
        sort_field = "created_at" unless valid_sort_fields.include?(sort_field)

        query = query.order("#{sort_field} #{sort_order}")

        # 计算总记录数
        total_count = query.count

        # 应用分页
        records = query.limit(page_size).offset((current_page - 1) * page_size)

        # 将记录转换为哈希数组，并添加文件 URL
        records_data = records.map do |record|
          record_hash = record.attributes
          file_field_names.each do |field_name|
            signed_id = record_hash[field_name]
            if signed_id.present?
              begin
                record_hash["#{field_name}_url"] = dynamic_record_file_url(
                  identifier: @table.api_identifier || @table.table_name,
                  id: record.id,
                  field_name: field_name,
                  host: request.host_with_port,
                  signed_id: signed_id
                )
                record_hash.delete(field_name)
              rescue => e
                Rails.logger.error "Error generating file URL for record #{record.id}, field #{field_name}: #{e.message}"
                record_hash["#{field_name}_url"] = nil
                record_hash.delete(field_name)
              end
            else
              record_hash["#{field_name}_url"] = nil
              record_hash.delete(field_name)
            end
          end
          record_hash
        end

        # 返回分页数据
        render json: {
          data: records_data,
          pagination: {
            current: current_page,
            pageSize: page_size,
            total: total_count
          }
        }
      end

      # GET /api/v1/:identifier/:id
      def show
        file_field_names = @table.dynamic_fields.where(field_type: "file").pluck(:name)

        # 将记录转换为哈希，并添加文件 URL
        record_hash = @record.attributes
        file_field_names.each do |field_name|
          signed_id = record_hash[field_name]
          if signed_id.present?
            begin
              record_hash["#{field_name}_url"] = dynamic_record_file_url(
                identifier: @table.api_identifier || @table.table_name,
                id: @record.id,
                field_name: field_name,
                host: request.host_with_port,
                signed_id: signed_id
              )
              record_hash.delete(field_name)
            rescue => e
              Rails.logger.error "Error generating file URL for record #{@record.id}, field #{field_name}: #{e.message}"
              record_hash["#{field_name}_url"] = nil
              record_hash.delete(field_name)
            end
          else
            record_hash["#{field_name}_url"] = nil
            record_hash.delete(field_name)
          end
        end

        render json: record_hash
      end

      def create
        model_class = DynamicTableService.get_dynamic_model(@table)

        # 1. 分离普通参数和文件参数
        regular_params = record_params.except(*file_field_names)
        file_params = record_params.slice(*file_field_names)

        # 2. 使用普通参数初始化记录
        @record = model_class.new(regular_params)

        puts "创建前的记录 (仅普通参数): #{@record.inspect}"
        puts "普通参数: #{regular_params.inspect}"
        puts "文件参数: #{file_params.inspect}"

        # 3. 处理文件字段并更新记录实例
        handle_file_fields(@record, file_params) # 传递只包含文件字段的参数

        # 4. 保存记录
        if @record.save
          puts "保存后的记录: #{@record.reload.inspect}"
          trigger_webhook("create", @record)
          # 为响应添加文件URL
          response_data = prepare_record_with_file_urls(@record)
          render json: response_data, status: :created # 返回包含URL的记录
        else
          puts "保存失败: #{@record.errors.full_messages}"
          render json: { error: @record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update
        # 1. 分离普通参数和文件参数
        regular_params = record_params.except(*file_field_names)
        file_params = record_params.slice(*file_field_names)

        puts "更新前的记录: #{@record.inspect}"
        puts "普通参数: #{regular_params.inspect}"
        puts "文件参数: #{file_params.inspect}"

        # 2. 处理文件字段并更新记录实例
        # 注意：handle_file_fields 直接修改 @record 实例
        handle_file_fields(@record, file_params)

        # 3. 使用普通参数更新记录的其他字段
        # 由于 handle_file_fields 已经修改了 @record 实例上的文件字段,
        # 调用 update 时，这些更改也会被包含在内。
        if @record.update(regular_params)
          puts "更新后的记录: #{@record.reload.inspect}"
          trigger_webhook("update", @record)

          # 为响应添加文件URL
          response_data = prepare_record_with_file_urls(@record)
          render json: response_data
        else
          puts "更新失败: #{@record.errors.full_messages}"
          render json: { error: @record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end



      # DELETE /api/v1/:identifier/:id
      def destroy
        record_data = @record.attributes
        @record.destroy
        # 触发 Webhook 回调
        trigger_webhook("destroy", record_data)
        head :no_content
      end

      private

      def prepare_record_with_file_urls(record)
        file_field_names = @table.dynamic_fields.where(field_type: "file").pluck(:name)
        record_hash = record.attributes

        file_field_names.each do |field_name|
          signed_id = record_hash[field_name]
          if signed_id.present?
            begin
              record_hash["#{field_name}_url"] = dynamic_record_file_url(
                identifier: @table.api_identifier || @table.table_name,
                id: record.id,
                field_name: field_name,
                host: request.host_with_port,
                signed_id: signed_id
              )
            rescue => e
              record_hash["#{field_name}_url"] = nil
            end
          else
            record_hash["#{field_name}_url"] = nil
          end
          record_hash.delete(field_name) # 从响应中移除原始signed_id
        end

        record_hash
      end


      def handle_file_fields(record, file_params_hash) # 参数名改为 file_params_hash 更清晰
        # 确保传入的是包含文件字段的哈希或参数对象
        return unless file_params_hash.is_a?(ActionController::Parameters) || file_params_hash.is_a?(Hash)
        puts "--- 处理文件字段 ---"
        # file_fields = @table.dynamic_fields.where(field_type: "file") # 这行不需要了
        # file_field_names = file_fields.pluck(:name) # 也不需要，因为我们已经知道哪些是文件字段

        file_params_hash.each do |field_name, file_value|
          # 确保我们只处理预期的文件字段（虽然调用者应该已经过滤好了）
          next unless file_field_names.include?(field_name.to_s)

          puts "处理字段: #{field_name}, 值类型: #{file_value.class}"

          if file_value.is_a?(ActionDispatch::Http::UploadedFile)
            # 上传文件处理
            begin
              blob = ActiveStorage::Blob.create_and_upload!(
                io: file_value.tempfile,
                filename: file_value.original_filename,
                content_type: file_value.content_type
              )
              record[field_name] = blob.signed_id
              puts "字段 #{field_name} 设置为 signed_id: #{blob.signed_id}"
            rescue => e
              Rails.logger.error "Error uploading file for field #{field_name}: #{e.message}"
              # 可以考虑在这里添加错误到 record.errors
              record.errors.add(field_name.to_sym, "文件上传失败: #{e.message}")
            end
          elsif file_value.blank? || file_value == "null" || file_value == "" # 明确处理空值或表示删除的字符串
            # 清除文件字段
            # 如果记录已经有关联的文件，需要先删除旧的 Blob
            if record.persisted? && record.send(field_name).present?
              begin
                old_blob = ActiveStorage::Blob.find_signed(record.send(field_name))
                old_blob&.purge_later # 异步删除
              rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
                # 如果找不到旧文件或签名无效，忽略
              rescue => e
                 Rails.logger.error "Error purging old blob for field #{field_name}: #{e.message}"
              end
            end
            record[field_name] = nil
            puts "字段 #{field_name} 设置为 nil"
            # else
            # 如果值不是 UploadedFile 也不是 blank/null，则忽略，不改变现有值
            # puts "字段 #{field_name} 的值不是文件或空值，跳过处理。"
          end
        end
        puts "--- 文件字段处理完毕 ---"
      end

      def authorize_app_entity!
        provided_apikey = request.headers["X-Api-Key"] || params[:apikey]
        provided_apisecret = request.headers["X-Api-Secret"] || params[:apisecret]
        # 验证必要的参数
        unless provided_apikey.present? && provided_apisecret.present?
          render json: { error: "缺少必要的认证参数 apikey 和 apisecret" }, status: :unauthorized
          return nil
        end
        # 查找API密钥并验证
        api_key = ApiKey.find_by(apikey: provided_apikey)
        if api_key && api_key.apisecret == provided_apisecret && api_key.active?
          @app_entity = api_key.app_entity
        end


        if @app_entity.nil? || @app_entity.inactive?
          render json: { error: "无授权访问或应用不存在" }, status: :unauthorized
          nil
        end
      end

      # 添加自定义的 URL 帮助方法
      def dynamic_record_file_url(options = {})
        identifier = options[:identifier]
        id = options[:id]
        field_name = options[:field_name]
        host = options[:host]
        signed_id = options[:signed_id]
        appId = @app_entity.id
        url = "/api/v1/#{appId}/#{identifier}/#{id}/files/#{field_name}"

        if signed_id.present?
          begin
            blob = ActiveStorage::Blob.find_signed(signed_id)
            if blob&.filename.present?
              url += "/#{CGI.escape(blob.filename.to_s)}"
            end
          rescue => e
            Rails.logger.error "Error getting filename for signed_id #{signed_id}: #{e.message}"
          end
        end
        url
      end

      def find_table_by_identifier
        unless @app_entity
          render json: { error: "应用未授权或不存在" }, status: :unauthorized
          return
        end

        identifier = params[:identifier].to_s.downcase
        @table = @app_entity.dynamic_tables.find_by(api_identifier: identifier) ||
                 @app_entity.dynamic_tables.find_by("LOWER(table_name) = ?", identifier)

        unless @table
          render json: { error: "找不到表格: #{identifier}" }, status: :not_found
          nil
        end
      end

      def find_record
        puts "Finding record with ID: #{params[:id]} in table: #{@table.table_name}"
        model_class = DynamicTableService.get_dynamic_model(@table)
        puts "Model class: #{model_class}"
        puts "Table name: #{model_class.table_name}"
        puts "Available columns: #{model_class.column_names.inspect}"
        @record = model_class.find_by(id: params[:id])
        puts "Record found: #{@record.inspect}"

        unless @record
          puts "Record not found!"
          render json: { error: "找不到记录 ##{params[:id]}" }, status: :not_found
          return false
        end

        true
      end

      def record_params
        # 允许所有定义的字段（包括文件字段）
        # 在 controller action 中再分离它们
        permitted_fields = @table.dynamic_fields.pluck(:name).map(&:to_sym)
        params.permit(*permitted_fields)
      end

      def file_field_names
        # 缓存结果以提高效率
        @file_field_names ||= @table.dynamic_fields.where(field_type: "file").pluck(:name)
      end
    end
  end
end
