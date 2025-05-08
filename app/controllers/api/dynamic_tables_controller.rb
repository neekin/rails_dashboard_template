module Api
  class DynamicTablesController < AdminController
    before_action :authorize_access_request!

    before_action :set_and_authorize_target_app_entity_for_index_create, only: [ :index, :create ]
    before_action :set_and_authorize_dynamic_table_and_app_entity, only: [ :show, :update, :destroy ]

    # GET /api/dynamic_tables
    def index
      # 获取查询参数
      query_params = params.permit(:current, :pageSize, :query, :appId, :sortField, :sortOrder).to_h
      current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
      page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

      # 解析过滤条件
      filters = JSON.parse(query_params["query"] || "{}").except("current", "pageSize")

      # 构建基础查询
      tables = @app_entity.dynamic_tables
      # 根据 appId 过滤表格
      if query_params["appId"].present?
        tables = tables.where(app_entity_id: query_params["appId"])
      end
      # 动态构建查询条件
      filters.each do |key, value|
        # 确保只对 DynamicTable 的列进行过滤
        if DynamicTable.column_names.include?(key.to_s) && value.present?
          tables = tables.where("#{key} LIKE ?", "%#{value}%")
        end
      end

      # 处理排序
      sort_field = query_params["sortField"].present? ? query_params["sortField"] : "created_at"
      sort_order = query_params["sortOrder"] == "ascend" ? "ASC" : "DESC"

      # 确保排序字段是有效的列
      valid_sort_fields = DynamicTable.column_names
      sort_field = "created_at" unless valid_sort_fields.include?(sort_field)

      tables = tables.order("#{sort_field} #{sort_order}")

      # 计算总记录数
      total_count = tables.count

      # 应用分页
      tables = tables.limit(page_size).offset((current_page - 1) * page_size)

      # 返回分页数据
      render json: {
        data: tables.as_json, # 使用as_json方法会自动包含api_url
        pagination: {
          current: current_page,
          pageSize: page_size,
          total: total_count
        }
      }
    end

    # POST /api/dynamic_tables
    def create
      # 明确检查表名
      if params[:table_name].blank?
        render json: { error: "表格名称不能为空" }, status: :unprocessable_entity
        return
      end

      # 检查表名是否以数字开头
      if params[:table_name].match(/\A\d/)
        render json: { error: "表格名称不能以数字开头" }, status: :unprocessable_entity
        return
      end

      # app_entity_id 来自 authorize_app_entity! 中的 @app_entity
      app_entity = @app_entity

      # 检查表名在当前 AppEntity 下是否已存在
      if app_entity.dynamic_tables.exists?(table_name: params[:table_name])
        render json: { error: "表格名称在此应用下已存在" }, status: :unprocessable_entity
        return
      end

      table = nil # 初始化 table 变量
      ActiveRecord::Base.transaction do
        # 创建表格元数据记录
        table = DynamicTable.new(
          table_name: params[:table_name],
          api_identifier: params[:api_identifier],
          webhook_url: params[:webhook_url],
          app_entity_id: app_entity.id
          # schema_status: :pending # 如果添加了状态字段
        )
        table.save!

        # 派发作业以创建物理表结构
        AlterDynamicTableJob.perform_later(table.id, :ensure_table_exists)

        # 创建字段元数据记录并派发作业以添加物理列
        if params[:fields].present?
          params[:fields].each do |field_params|
            unique_value = ActiveRecord::Type::Boolean.new.cast(field_params[:unique]) || false
            required_value = ActiveRecord::Type::Boolean.new.cast(field_params[:required]) || false

            # 创建 DynamicField 元数据记录
            created_field = table.dynamic_fields.create!(
              name: field_params[:name],
              field_type: field_params[:field_type],
              required: required_value,
              unique: unique_value
              # schema_status: :pending # 如果添加了状态字段
            )
            # 派发作业以在物理表中添加列
            AlterDynamicTableJob.perform_later(table.id, :add_field, { dynamic_field_id: created_field.id })
          end
        end
      end # 事务结束

      # 返回 202 Accepted，表示请求已接受，正在后台处理
      render json: { message: "表格创建请求已提交，正在后台处理。", table_id: table.id }, status: :accepted

    rescue ActiveRecord::RecordInvalid => e
      error_details = e.record.errors.full_messages.join(", ")
      Rails.logger.error "RecordInvalid during DynamicTable/Field creation: #{e.message}. Details: #{error_details}"
      render json: { error: e.message, details: error_details }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "创建表格元数据失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "创建表格元数据时出错: #{e.message}" }, status: :internal_server_error
    end


    # GET /api/dynamic_tables/:id
    def show
      table = DynamicTable.find(params[:id])
      # 确保当前用户有权查看此表 (通过 app_entity 关联)
      if table.app_entity.user_id != current_user.id
        render json: { error: "您无权查看此表格" }, status: :forbidden
        return
      end
      render json: table.as_json(include: :dynamic_fields)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "表格不存在" }, status: :not_found
    end

    # PATCH/PUT /api/dynamic_tables/:id
    def update
      table = DynamicTable.find(params[:id])
      # 确保当前用户有权操作此表 (通过 app_entity 关联)
      if table.app_entity.user_id != current_user.id
        render json: { error: "您无权操作此表格" }, status: :forbidden
        return
      end

      ActiveRecord::Base.transaction do
        # 更新表的基本信息 (同步)
        if params[:table_name].present?
          if params[:table_name].match(/\A\d/)
            render json: { error: "表格名称不能以数字开头" }, status: :unprocessable_entity
            return
          end
          # 检查新表名是否在当前 AppEntity 下已存在 (排除自身)
          if table.app_entity.dynamic_tables.where.not(id: table.id).exists?(table_name: params[:table_name])
            render json: { error: "表格名称在此应用下已存在" }, status: :unprocessable_entity
            return
          end
          table.table_name = params[:table_name]
        end

        table.api_identifier = params[:api_identifier] if params.key?(:api_identifier)
        table.webhook_url = params[:webhook_url] if params.key?(:webhook_url)
        table.save! # 保存表的基本信息

        # 处理字段的更新、创建、删除 (异步)
        if params[:fields].present?
          existing_field_ids = table.dynamic_fields.pluck(:id)
          incoming_field_params_by_id = params[:fields].select { |fp| fp[:id].present? }.index_by { |fp| fp[:id].to_i }
          new_field_params = params[:fields].select { |fp| fp[:id].blank? }

          # 1. 删除字段
          fields_to_delete_ids = existing_field_ids - incoming_field_params_by_id.keys
          fields_to_delete = table.dynamic_fields.where(id: fields_to_delete_ids)

          fields_to_delete.each do |field|
            # 派发作业以删除物理列
            AlterDynamicTableJob.perform_later(table.id, :remove_field, { dynamic_field_id: field.id, field_name: field.name })
            field.destroy! # 删除元数据记录
          end

          # 2. 更新现有字段
          incoming_field_params_by_id.each do |field_id, field_params|
            field = table.dynamic_fields.find_by(id: field_id)
            next unless field # 如果字段在此期间被删除，则跳过

            # 准备字段更新的属性
            field_update_attributes = {
              name: field_params[:name],
              field_type: field_params[:field_type],
              required: ActiveRecord::Type::Boolean.new.cast(field_params[:required]) || false,
              unique: ActiveRecord::Type::Boolean.new.cast(field_params[:unique]) || false
            }

            # 检查是否需要重命名物理列
            if field.name != field_update_attributes[:name]
              AlterDynamicTableJob.perform_later(table.id, :rename_field, {
                dynamic_field_id: field.id,
                old_name: field.name,
                new_name: field_update_attributes[:name]
              })
            end

            # 检查是否需要更改物理列类型
            if field.field_type != field_update_attributes[:field_type]
              AlterDynamicTableJob.perform_later(table.id, :change_type, {
                dynamic_field_id: field.id,
                field_name: field_update_attributes[:name], # 使用新名称，如果已更改
                new_type_string: field_update_attributes[:field_type],
                old_type_string: field.field_type
              })
            end

            # 检查是否需要更改唯一约束
            # 注意：如果字段名也变了，确保在 rename_field 作业之后执行，或者 change_unique_constraint 作业使用新名称
            if field.unique != field_update_attributes[:unique]
              AlterDynamicTableJob.perform_later(table.id, :change_unique_constraint, {
                dynamic_field_id: field.id,
                field_name: field_update_attributes[:name], # 使用新名称
                add_unique: field_update_attributes[:unique]
              })
            end

            # 更新 DynamicField 元数据记录
            field.update!(field_update_attributes)
          end

          # 3. 创建新字段
          new_field_params.each do |field_params|
            created_field = table.dynamic_fields.create!(
              name: field_params[:name],
              field_type: field_params[:field_type],
              required: ActiveRecord::Type::Boolean.new.cast(field_params[:required]) || false,
              unique: ActiveRecord::Type::Boolean.new.cast(field_params[:unique]) || false
            )
            AlterDynamicTableJob.perform_later(table.id, :add_field, { dynamic_field_id: created_field.id })
          end
        end
      end # 事务结束

      render json: { message: "表格更新请求已提交，正在后台处理。" }, status: :accepted

    rescue ActiveRecord::RecordNotFound
      render json: { error: "表格不存在" }, status: :not_found
    rescue ActiveRecord::RecordInvalid => e
      error_details = e.record.errors.full_messages.join(", ")
      Rails.logger.error "RecordInvalid during DynamicTable/Field update: #{e.message}. Details: #{error_details}"
      render json: { error: e.message, details: error_details }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "更新表格元数据失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "更新表格元数据时出错: #{e.message}" }, status: :internal_server_error
    end

    # DELETE /api/dynamic_tables/:id
    def destroy
      table = DynamicTable.find(params[:id])
      # 确保当前用户有权操作此表
      if table.app_entity.user_id != current_user.id
        render json: { error: "您无权操作此表格" }, status: :forbidden
        return
      end

      # 考虑将物理表删除和元数据删除都放入一个或多个后台作业中
      # 这里为了简化，暂时保持同步，但可以修改为异步
      ActiveRecord::Base.transaction do
        table_name_to_drop = "dyn_#{table.id}" # 使用 DynamicTableService.physical_table_name(table) 会更好

        # 先删除物理表
        if ActiveRecord::Base.connection.table_exists?(table_name_to_drop)
          begin
            ActiveRecord::Base.connection.drop_table(table_name_to_drop, force: :cascade)
            Rails.logger.info "物理表 #{table_name_to_drop} 已删除。"
          rescue ActiveRecord::StatementInvalid => e
            Rails.logger.warn "尝试删除物理表 #{table_name_to_drop} 失败 (可能已被删除或不存在): #{e.message}"
          end
        else
          Rails.logger.info "物理表 #{table_name_to_drop} 不存在，无需删除。"
        end

        # 然后删除表元数据记录 (会级联删除关联的 DynamicField 记录)
        table.destroy!
        Rails.logger.info "DynamicTable 记录 ID: #{params[:id]} 已删除。"
      end

      render json: { status: "success", message: "表格已成功删除。" }

    rescue ActiveRecord::RecordNotFound
      render json: { error: "表格不存在" }, status: :not_found
    rescue => e
      Rails.logger.error "删除表格失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "删除表格时发生错误: #{e.message}" }, status: :internal_server_error
    end

    private

    def set_and_authorize_target_app_entity_for_index_create
      app_entity_id_param = params[:app_entity_id] || params[:app_entity] || params[:appId]

      if app_entity_id_param.present?
        @app_entity = AppEntity.find_by(id: app_entity_id_param)
        unless @app_entity
          render json: { error: "指定应用不存在" }, status: :not_found and return
        end

        unless current_user.admin? || @app_entity.user_id == current_user.id
          render json: { error: "您无权操作此应用" }, status: :forbidden and return
        end
      elsif action_name == "create" # 创建时必须提供 appId
        render json: { error: "创建表格需要提供应用ID (appId)" }, status: :unprocessable_entity and return
      else # index 且无 appId
        @app_entity = nil # 管理员将查询所有，普通用户将查询其拥有的
      end
    end

    def set_and_authorize_dynamic_table_and_app_entity
      @dynamic_table = DynamicTable.find_by(id: params[:id])
      unless @dynamic_table
        render json: { error: "表格不存在" }, status: :not_found and return
      end

      @app_entity = @dynamic_table.app_entity
      unless @app_entity
        render json: { error: "表格未关联到任何应用" }, status: :internal_server_error and return # 数据不一致
      end

      unless current_user.admin? || @app_entity.user_id == current_user.id
        render json: { error: "您无权操作此表格" }, status: :forbidden and return
      end
    end
  end
end
