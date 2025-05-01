module Api
  module V1
    class DynamicApiController < ApiController
      # include Rails.application.routes.url_helpers

      before_action :find_table_by_identifier
      before_action :find_record, only: [ :show, :update, :destroy, :serve_file ]
      def serve_file
        field_name = params[:field_name].to_s.split("/").first

        # 1. 验证字段是否存在且为文件类型
        dynamic_field = @table.dynamic_fields.find_by(name: field_name, field_type: "file")
        unless dynamic_field
          render json: { error: "无效的文件字段: #{field_name}" }, status: :not_found
          return
        end

        # 2. 获取存储在记录中的 signed_id
        signed_id = @record.send(field_name)
        unless signed_id.present?
          render json: { error: "记录 ##{@record.id} 没有字段 '#{field_name}' 的文件" }, status: :not_found
          return
        end

        # 3. 查找 Active Storage Blob
        begin
          blob = ActiveStorage::Blob.find_signed!(signed_id)
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
          render json: { error: "无法找到或验证文件" }, status: :not_found
          return
        end

        # 4. 根据配置文件和存储服务类型决定服务方式
        begin
          # 检查是否是 S3 兼容服务
          is_s3_service = defined?(ActiveStorage::Service::S3Service) && blob.service.is_a?(ActiveStorage::Service::S3Service)


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
      # GET /api/v1/:identifier
      def index
        # 获取查询参数
        query_params = params.permit(:current, :pageSize, :query, :sortField, :sortOrder, :identifier).to_h
        current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
        page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

        # 获取文件字段名称列表
        file_field_names = @table.dynamic_fields.where(field_type: "file").pluck(:name)
        table_identifier = params[:identifier] # 使用路由中的标识符

        # 创建连接到物理表的模型
        model_class = DynamicTableService.get_dynamic_model(@table)

        # 构建基础查询
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
        sort_order = query_params["sortOrder"] == "ascend" ? "ASC" : "DESC"

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
                # 保存文件URL到新字段，字段名为 field_name_url
                record_hash["#{field_name}_url"] = dynamic_record_file_url(
                  identifier: table_identifier,
                  id: record.id,
                  field_name: field_name,
                  host: request.host_with_port,
                  signed_id: signed_id
                )
                # 删除存储signed_id的原始字段
                record_hash.delete(field_name)

                Rails.logger.info "generating file URL for record #{record.id}, field #{field_name}: #{record_hash["#{field_name}_url"]}"
              rescue => e
                Rails.logger.error "Error generating file URL for record #{record.id}, field #{field_name}: #{e.message}"
                record_hash["#{field_name}_url"] = nil
                record_hash.delete(field_name)
              end
            else
              # 没有文件时也删除原始字段，设置URL为nil
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
        table_identifier = params[:identifier] # 使用路由中的标识符
        # 将记录转换为哈希，并添加文件 URL
        record_hash = @record.attributes
        file_field_names.each do |field_name|
          signed_id = record_hash[field_name]
          if signed_id.present?
            begin
              # 保存文件URL到新字段，字段名为 field_name_url
              record_hash["#{field_name}_url"] = dynamic_record_file_url(
                identifier: table_identifier,
                id: @record.id,
                field_name: field_name,
                host: request.host_with_port,
                signed_id: signed_id
              )
              # 删除存储signed_id的原始字段
              record_hash.delete(field_name)
            rescue => e
              Rails.logger.error "Error generating file URL for record #{@record.id}, field #{field_name}: #{e.message}"
              record_hash["#{field_name}_url"] = nil
              record_hash.delete(field_name)
            end
          else
            # 没有文件时也删除原始字段，设置URL为nil
            record_hash["#{field_name}_url"] = nil
            record_hash.delete(field_name)
          end
        end

        render json: record_hash # 返回处理后的哈希
      end

      # POST /api/v1/:identifier
      def create
        model_class = DynamicTableService.get_dynamic_model(@table)
        @record = model_class.new(record_params)

        if @record.save
          render json: @record, status: :created
        else
          render json: { error: @record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # PUT/PATCH /api/v1/:identifier/:id
      def update
        if @record.update(record_params)
          render json: @record
        else
          render json: { error: @record.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/:identifier/:id
      def destroy
        @record.destroy
        head :no_content
      end

      private

      # 添加自定义的 URL 帮助方法
      # 修改在 private 部分的 URL 帮助方法
      def dynamic_record_file_url(options = {})
        identifier = options[:identifier]
        id = options[:id]
        field_name = options[:field_name]
        host = options[:host] # 这个 host 仅用于生成指向 Rails 应用的 URL
        signed_id = options[:signed_id]

        # 基础 URL 指向 Rails 的 serve_file 动作
        # 注意：这里不再需要 request.host_with_port，因为我们生成相对路径或使用配置好的 host
        # 如果需要绝对路径，确保 Rails 配置了 default_url_options
        # url = url_for(controller: 'api/v1/dynamic_api', action: :serve_file, identifier: identifier, id: id, field_name: field_name, only_path: true)
        # 或者手动构建相对路径
        url = "/api/v1/#{identifier}/#{id}/files/#{field_name}"


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

      def find_table_by_identifier
        identifier = params[:identifier].downcase
        # 先尝试通过API标识符查找，如果失败再尝试通过表名查找
        @table = DynamicTable.find_by(api_identifier: identifier) ||
                 DynamicTable.find_by("LOWER(table_name) = ?", identifier)

        unless @table
          render json: { error: "找不到表格: #{identifier}" }, status: :not_found
          false
        end
      end

      def find_record
        model_class = DynamicTableService.get_dynamic_model(@table)
        @record = model_class.find_by(id: params[:id])

        unless @record
          render json: { error: "找不到记录 ##{params[:id]}" }, status: :not_found
          false
        end
      end

      def record_params
        # 动态获取当前表的所有字段
        permitted_fields = @table.dynamic_fields.pluck(:name)
        params.require(:record).permit(permitted_fields)
      rescue ActionController::ParameterMissing
        # 如果没有提供record参数
        params.permit(permitted_fields)
      end
    end
  end
end
