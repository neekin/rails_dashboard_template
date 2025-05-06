module Api
  class DynamicFieldsController < AdminController
    before_action :validate_user_ownership!, only: [ :index, :create ]
    before_action :set_dynamic_table, only: [ :index, :create ]

    def index
      fields = @dynamic_table.dynamic_fields
      render json: { fields: fields, table_name: @dynamic_table.table_name }
    end

    # POST /api/dynamic_tables/:dynamic_table_id/dynamic_fields
    def create
      fields = params[:fields] || []
      updated_or_created_fields = []
      result = { success: true, fields: [] }

      begin
        # 使用事务包裹所有字段操作
        ActiveRecord::Base.transaction do
          fields.each do |field|
            # 统一参数处理方式
            field_params = case field
            when ActionController::Parameters
                            field.permit(:id, :name, :field_type, :required, :unique).to_h.symbolize_keys
            when Hash
                            field.symbolize_keys.slice(:id, :name, :field_type, :required, :unique)
            else
                            raise StandardError, "无效的字段格式: #{field.class}"
            end

            begin
              if field_params[:id].present?
                update_existing_field(field_params, @dynamic_table, updated_or_created_fields)
              else
                create_new_field(field_params, @dynamic_table, updated_or_created_fields)
              end
            rescue StandardError => e
              # 记录出错的字段
              Rails.logger.error "处理字段失败: #{e.message}\n#{e.backtrace.join("\n")}"
              # 设置错误标记并终止事务
              result = {
                success: false,
                error: "处理字段 '#{field_params[:name]}' 失败: #{e.message}"
              }
              raise ActiveRecord::Rollback
            end
          end
        end

        # 事务处理完成后，根据结果渲染响应
        if result[:success]
          render json: {
            fields: @dynamic_table.reload.dynamic_fields,
            table_name: @dynamic_table.table_name,
            app_entity_id: @dynamic_table.app_entity_id
          }, status: :created
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end

      rescue ActiveRecord::RecordNotFound => e
        render json: { error: "找不到指定的动态表: #{e.message}" }, status: :not_found
      rescue => e
        Rails.logger.error "创建字段时发生未预期错误: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: "处理字段时发生服务器错误: #{e.message}" }, status: :internal_server_error
      end
    end

    private

    def set_dynamic_table
      @dynamic_table = DynamicTable.find(params[:dynamic_table_id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "指定的动态表未找到" }, status: :not_found
    end

    def create_new_field(field, dynamic_table, updated_or_created_fields)
      # 首先验证字段参数
      if field[:name].blank?
        raise StandardError, "字段名不能为空"
      end

      # 创建新字段
      new_field = dynamic_table.dynamic_fields.new(field)

      # 保存字段记录
      new_field.save!

      # 添加到物理表
      result = DynamicTableService.add_field_to_physical_table(dynamic_table, new_field)

      # 检查结果
      unless result && result[:success]
        # 删除刚创建的记录，因为物理表操作失败
        new_field.destroy

        error_msg = result && result[:error] ?
                    result[:error] :
                    "处理字段 '#{field[:name]}' 的物理表操作时发生意外情况"

        raise StandardError, error_msg
      end

      updated_or_created_fields << new_field
    end

    def update_existing_field(field, dynamic_table, updated_or_created_fields)
      existing_field = DynamicField.find(field[:id])

      # 如果字段名称发生变化，更新物理表中的列名
      if existing_field.name != field[:name]
        begin
          DynamicTableService.rename_field_in_physical_table(dynamic_table, existing_field.name, field[:name])
        rescue StandardError => e
          # 如果服务层抛出异常，将其包装后重新抛出，以便事务回滚
          raise StandardError, "重命名字段 '#{existing_field.name}' 到 '#{field[:name]}' 失败: #{e.message}"
        end
      end

      # 如果字段类型发生变化，需要处理数据库的限制
      if existing_field.field_type != field[:field_type]
        begin
          DynamicTableService.change_field_type(dynamic_table, field[:name], field[:field_type], existing_field.field_type)
        rescue StandardError => e
          # 如果服务层抛出异常，将其包装后重新抛出
          raise StandardError, "更改字段 '#{field[:name]}' 类型从 '#{existing_field.field_type}' 到 '#{field[:field_type]}' 失败: #{e.message}"
        end
      end

      # 如果唯一性约束发生变化，更新物理表的唯一性约束
      if existing_field.unique != field[:unique]
        Rails.logger.info "更新字段唯一性约束: #{field[:name]} 为 #{field[:unique]}"
        table_name = DynamicTableService.physical_table_name(dynamic_table)
        result = nil # 初始化 result

        if field[:unique]
          # 添加唯一约束
          result = DynamicTableService.add_unique_index(table_name, field[:name])
        else
          # 移除唯一约束
          result = DynamicTableService.remove_unique_index(table_name, field[:name])
        end

        unless result && result[:success] # 确保 result 不为 nil
          Rails.logger.warn "唯一索引修改失败: #{result ? result[:error] : '未知错误'}"
          raise StandardError, (result ? result[:error] : "更新唯一约束时发生未知错误")
        end
      end

      # 更新字段
      existing_field.update!(field)
      updated_or_created_fields << existing_field
    end
  end
end
