module Api
  module V1
    class DynamicApiController < ApiController
      before_action :find_table_by_identifier
      before_action :find_record, only: [ :show, :update, :destroy ]

      # GET /api/v1/:identifier
      def index
        # 获取查询参数
        query_params = params.permit(:current, :pageSize, :query, :sortField, :sortOrder).to_h
        current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
        page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

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

        # 返回分页数据
        render json: {
          data: records,
          pagination: {
            current: current_page,
            pageSize: page_size,
            total: total_count
          }
        }
      end

      # GET /api/v1/:identifier/:id
      def show
        render json: @record
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
