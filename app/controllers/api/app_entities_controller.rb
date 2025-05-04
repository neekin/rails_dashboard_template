module Api
  class AppEntitiesController < AdminController
    before_action :set_app_entity, only: [ :show, :update, :destroy, :manage_api_keys ]
    before_action :authorize_user!, only: [ :update, :destroy, :manage_api_keys ]
    before_action :authorize_access_request!

    # GET /api/app_entities
    def index
      # 获取查询参数
      query_params = params.permit(:current, :pageSize, :query, :sortField, :sortOrder).to_h
      current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
      page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

      # 解析过滤条件
      filters = JSON.parse(query_params["query"] || "{}").except("current", "pageSize")

      # 构建基础查询
      # 构建基础查询，仅限当前用户的 AppEntity
      entities = current_user.app_entities

      # 动态构建查询条件
      filters.each do |key, value|
        entities = entities.where("#{key} LIKE ?", "%#{value}%")
      end

      # 处理排序
      sort_field = query_params["sortField"].present? ? query_params["sortField"] : "created_at"
      sort_order = query_params["sortOrder"] == "ascend" ? "ASC" : "DESC"

      # 确保排序字段是有效的列
      valid_sort_fields = [ "id", "name", "status", "created_at", "updated_at" ]
      sort_field = "created_at" unless valid_sort_fields.include?(sort_field)

      entities = entities.order("#{sort_field} #{sort_order}")

      # 计算总记录数
      total_count = entities.count

      # 应用分页
      entities = entities.limit(page_size).offset((current_page - 1) * page_size)

      # 返回分页数据
      render json: {
        data: entities.as_json,
        pagination: {
          current: current_page,
          pageSize: page_size,
          total: total_count
        }
      }
    end


    # GET /api/app_entities/:id
    def show
      render json: @app_entity
    end

    # POST /api/app_entities
    def create
      @app_entity = AppEntity.new(app_entity_params.merge(user_id: current_user.id))

      if @app_entity.save
        # 同时创建一个默认的API密钥
        @api_key = @app_entity.api_keys.create!
        render json: {
          app_entity: @app_entity,
          api_key: {
            apikey: @api_key.apikey,
            apisecret: @api_key.apisecret
          }
        }, status: :created
      else
        render json: @app_entity.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/app_entities/:id
    def update
      if @app_entity.update(app_entity_params)
        render json: @app_entity
      else
        render json: @app_entity.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/app_entities/:id
    def destroy
      ActiveRecord::Base.transaction do
        # 删除关联的 DynamicTable 和物理表
        @app_entity.dynamic_tables.each do |table|
          table_name = "dyn_#{table.id}"

          # 删除物理表
          if ActiveRecord::Base.connection.table_exists?(table_name)
            begin
              ActiveRecord::Base.connection.drop_table(table_name, force: :cascade)
            rescue ActiveRecord::StatementInvalid => e
              Rails.logger.warn "删除物理表 #{table_name} 失败: #{e.message}"
            end
          end

          # 删除表记录（会级联删除关联的字段）
          table.destroy!
        end

        # 删除 AppEntity
        @app_entity.destroy!

        render json: { status: "success", message: "应用及其关联表格已删除" }
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "应用不存在" }, status: :not_found
    rescue => e
      Rails.logger.error "删除应用失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: e.message }, status: :internal_server_error
    end

    # 管理API密钥
    def manage_api_keys
      case params[:action_type]
      when "create"
        # 创建新的API密钥
        api_key = @app_entity.api_keys.create!
        render json: {
          apikey: api_key.apikey,
          apisecret: api_key.apisecret
        }, status: :created
      when "list"
        # 列出所有API密钥
        keys = @app_entity.api_keys
        render json: keys
      when "toggle_status"
        # 切换API密钥状态
        api_key = @app_entity.api_keys.find(params[:key_id])
        new_status = params[:active].to_s == "true"
        api_key.update!(active: new_status)
        render json: {
          status: "success",
          message: "API密钥已#{new_status ? '启用' : '停用'}"
        }
      when "update"
        # 更新API密钥备注
        api_key = @app_entity.api_keys.find(params[:key_id])
        api_key.update!(remark: params[:remark])
        render json: {
          status: "success",
          message: "API密钥备注已更新"
        }
      when "delete"
        # 删除API密钥
        api_key = @app_entity.api_keys.find(params[:key_id])
        api_key.destroy!
        render json: { status: "success", message: "API密钥已删除" }
      else
        render json: { error: "未知的操作类型" }, status: :bad_request
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "API密钥不存在" }, status: :not_found
    rescue => e
      Rails.logger.error "管理API密钥失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: e.message }, status: :internal_server_error
    end


    private

    # 设置当前的 AppEntity
    def set_app_entity
      @app_entity = AppEntity.find(params[:id])
    end

    # 允许的参数
    def app_entity_params
      params.require(:app_entity).permit(:name, :description, :status)
    end
  end
end
