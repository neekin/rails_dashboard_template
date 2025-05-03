module Api
  class DynamicTablesController < ApiController
    def index
      # 获取查询参数
      query_params = params.permit(:current, :pageSize, :query).to_h
      current_page = query_params["current"].to_i > 0 ? query_params["current"].to_i : 1
      page_size = query_params["pageSize"].to_i > 0 ? query_params["pageSize"].to_i : 10

      # 解析过滤条件
      filters = JSON.parse(query_params["query"] || "{}").except("current", "pageSize")

      # 构建基础查询
      tables = DynamicTable.all

      # 动态构建查询条件
      filters.each do |key, value|
        tables = tables.where("#{key} LIKE ?", "%#{value}%")
      end

      # 处理排序
      sort_field = query_params["sortField"].present? ? query_params["sortField"] : "created_at"
      sort_order = query_params["sortOrder"] == "ascend" ? "ASC" : "DESC"

      # 确保排序字段是有效的列
      valid_sort_fields = [ "id", "table_name", "created_at", "updated_at" ]
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
      # 检查 app_entity 参数是否存在且有效
      app_entity_id = params[:app_entity]
      if app_entity_id.blank? || !AppEntity.exists?(app_entity_id)
        render json: { error: "非法应用或应用不存在" }, status: :unprocessable_entity
        return
      end
      # 检查表名在当前 AppEntity 下是否已存在
      if AppEntity.find(app_entity_id).dynamic_tables.exists?(table_name:  params[:table_name])
        render json: { error: "表格名称在此应用下已存在" }, status: :unprocessable_entity
        return
      end

      ActiveRecord::Base.transaction do
        # 创建表格
        table = DynamicTable.new(
          table_name: params[:table_name],
          api_identifier: params[:api_identifier],
          app_entity_id: app_entity_id
        )
        table.save!

        # 创建字段
        if params[:fields].present?
          params[:fields].each do |field|
            table.dynamic_fields.create!(
              name: field[:name],
              field_type: field[:field_type],
              required: field[:required]
            )
          end
        end

        # 创建物理表
        DynamicTableService.create_physical_table(table)

        render json: table, status: :created
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def show
      table = DynamicTable.find(params[:id])
      render json: table.as_json(include: :dynamic_fields)
    end

    def update
      ActiveRecord::Base.transaction do
        table = DynamicTable.find(params[:id])

        # 先保存表的基本信息
        if params[:table_name].present?
          if params[:table_name].match(/\A\d/)
            render json: { error: "表格名称不能以数字开头" }, status: :unprocessable_entity
            return
          end

          if DynamicTable.where.not(id: table.id).exists?(table_name: params[:table_name])
            render json: { error: "表格名称已存在" }, status: :unprocessable_entity
            return
          end

          table.table_name = params[:table_name]
        end

        if params.key?(:api_identifier)
          table.api_identifier = params[:api_identifier]
        end

        # 保存表的基本信息
        table.save!

        # 如果提供了fields参数，更新字段
        if params[:fields].present?
          existing_fields = table.dynamic_fields

          # 找出需要删除的字段
          incoming_field_ids = params[:fields].map { |field| field[:id] }.compact
          fields_to_delete = existing_fields.where.not(id: incoming_field_ids)

          # 删除字段
          fields_to_delete.each do |field|
            begin
              DynamicTableService.remove_field_from_physical_table(table, field)
            rescue => e
              Rails.logger.error "删除字段时出错: #{e.message}"
              # 如果是测试环境，重新抛出异常以便测试能捕获到
              raise e if Rails.env.test?
            end
            field.destroy!
          end

          # 更新或创建字段
          params[:fields].each do |field_params|
            if field_params[:id].present?
              # 更新现有字段
              field = existing_fields.find_by(id: field_params[:id])

              # 如果找不到字段，跳过
              if field.nil?
                Rails.logger.warn("字段ID #{field_params[:id]} 不存在，跳过更新")
                next
              end

              # 检查是否需要更改物理表中的列名
              begin
                if field.name != field_params[:name]
                  Rails.logger.info("正在重命名字段: #{field.name} -> #{field_params[:name]}")
                  DynamicTableService.rename_field_in_physical_table(table, field.name, field_params[:name])
                end

                # 检查是否需要更改字段类型
                if field.field_type != field_params[:field_type]
                  Rails.logger.info("正在更改字段类型: #{field.name} 从 #{field.field_type} 到 #{field_params[:field_type]}")
                  DynamicTableService.change_field_type(table, field_params[:name], field_params[:field_type], field.field_type)
                end
              rescue => e
                Rails.logger.error "更新字段结构时出错: #{e.message}\n#{e.backtrace.join("\n")}"
                # 测试环境抛出异常
                raise e if Rails.env.test?
              end

              # 更新字段记录
              field.update!(
                name: field_params[:name],
                field_type: field_params[:field_type],
                required: field_params[:required]
              )
            else
              # 创建新字段
              new_field = table.dynamic_fields.create!(
                name: field_params[:name],
                field_type: field_params[:field_type],
                required: field_params[:required]
              )

              # 在物理表中添加列
              begin
                DynamicTableService.add_field_to_physical_table(table, new_field)
              rescue => e
                Rails.logger.error "添加新字段时出错: #{e.message}\n#{e.backtrace.join("\n")}"
                # 测试环境抛出异常
                raise e if Rails.env.test?
              end
            end
          end
        end

        render json: { status: "success" }
      end
    rescue ActiveRecord::RecordNotFound => e
      render json: { error: "表格不存在" }, status: :not_found
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "更新表格失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: e.message }, status: :internal_server_error
    end

    def destroy
      begin
        ActiveRecord::Base.transaction do
          table = DynamicTable.find(params[:id])
          table_name = "dyn_#{table.id}"

          # 先删除物理表，使用安全检查
          if ActiveRecord::Base.connection.table_exists?(table_name)
            begin
              ActiveRecord::Base.connection.drop_table(table_name, force: :cascade)
            rescue ActiveRecord::StatementInvalid => e
              # 记录错误但继续执行，可能表已被删除
              Rails.logger.warn "删除物理表 #{table_name} 失败: #{e.message}"
            end
          end

          # 然后删除表记录（会级联删除关联的字段）
          table.destroy!

          render json: { status: "success", message: "表格已删除" }
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "表格不存在" }, status: :not_found
      rescue => e
        Rails.logger.error "删除表格失败: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end
end
