module Api
  module V1
    class DynamicApiController < ApiController
      before_action :authorize_app_entity!
      # include Rails.application.routes.url_helpers

      before_action :find_table_by_identifier
      before_action :find_record, only: [ :show, :update, :destroy ]
      # 跳过 `authorize_app_entity!` 和 `find_table_by_identifier` 对 `serve_file` 方法的拦截
      skip_before_action :authorize_app_entity!, only: [ :serve_file ]
      skip_before_action :find_table_by_identifier, only: [ :serve_file ]

      def serve_file
        app_id = params[:appId] # 从 URL 参数中获取 appId
        identifier = params[:identifier] # 从 URL 参数中获取表格标识符
        field_name = params[:field_name].to_s.split("/").first # 从 URL 参数中获取字段名称
        # 验证 appId 是否有效
        @app_entity = AppEntity.find_by(id: app_id)
        unless @app_entity
          render json: { error: "无效的应用 ID: #{app_id}" }, status: :not_found
          return
        end

        # 查找表格
        @table = @app_entity.dynamic_tables.find_by(api_identifier: identifier) ||
                 @app_entity.dynamic_tables.find_by("LOWER(table_name) = ?", identifier.downcase)
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
          render json: { error: "记录 ##{@record.id} 没有字段 '#{field_name}' 的文件" }, status: :not_found
          return
        end

        # 查找 Active Storage Blob
        begin
          blob = ActiveStorage::Blob.find_signed!(signed_id)
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
          render json: { error: "无法找到或验证文件" }, status: :not_found
          return
        end

        # 根据配置文件和存储服务类型决定服务方式
        begin
          is_s3_service = defined?(ActiveStorage::Service::S3Service) && blob.service.is_a?(ActiveStorage::Service::S3Service)

          if Rails.application.config.x.file_serving_strategy == :redirect && is_s3_service
            expires_in = 10.minutes
            disposition_param = params[:disposition] == "attachment" ? :attachment : :inline
            redirect_url = blob.url(expires_in: expires_in, disposition: disposition_param)
            redirect_to redirect_url, allow_other_host: true, status: :found
          else
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

      def authorize_app_entity!
        provided_token = request.headers["Authorization"] || params[:token]

        # 根据 token 查找 AppEntity
        @app_entity = AppEntity.find_by(token: provided_token)

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
        model_class = DynamicTableService.get_dynamic_model(@table)
        @record = model_class.find_by(id: params[:id])

        unless @record
          render json: { error: "找不到记录 ##{params[:id]}" }, status: :not_found
          false
        end
      end

      def record_params
        permitted_fields = @table.dynamic_fields.pluck(:name)
        params.require(:record).permit(permitted_fields)
      rescue ActionController::ParameterMissing
        params.permit(permitted_fields)
      end
    end
  end
end
