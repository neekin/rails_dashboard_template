module Api
  class AppEntitiesController < AdminController
    before_action :set_app_entity, only: [ :show, :update, :destroy, :reset_token ]
    before_action :authorize_user!, only: [ :update, :destroy, :reset_token ]
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
        data: entities.as_json(except: [ :token ]),
        pagination: {
          current: current_page,
          pageSize: page_size,
          total: total_count
        }
      }
    end


    # GET /api/app_entities/:id
    def show
      render json: @app_entity.as_json(except: [ :token ])
    end

    # POST /api/app_entities
    def create
      @app_entity = AppEntity.new(app_entity_params.merge(user_id: current_user.id))

      if @app_entity.save
        render json: @app_entity, status: :created
      else
        render json: @app_entity.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/app_entities/:id
    def update
      if @app_entity.update(app_entity_params)
        render json: @app_entity.as_json(except: [ :token ])
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

    # 重置密钥
    def reset_token
      @app_entity.regenerate_token # 使用 has_secure_token 提供的 regenerate_token 方法
      render json: { token: @app_entity.token }, status: :ok
    rescue => e
      Rails.logger.error "重置密钥失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "重置密钥失败" }, status: :internal_server_error
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
