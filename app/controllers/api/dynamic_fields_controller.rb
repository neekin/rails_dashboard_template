module Api
  class DynamicFieldsController < AdminController
    before_action :set_dynamic_table, only: [ :index, :create ]
    before_action :validate_user_ownership!
    # before_action :authorize_table_access!, only: [ :index, :create ]
    before_action :authorize_access_request!

    def index
      fields = @dynamic_table.dynamic_fields
      render json: { fields: fields, table_name: @dynamic_table.table_name }
    end

    # POST /api/dynamic_tables/:dynamic_table_id/dynamic_fields
    def create
      fields = params[:fields] || []
      updated_or_created_fields = []
      error_message = nil

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
              # 设置错误信息并终止事务
              error_message = "处理字段 '#{field_params[:name]}' 失败: #{e.message}"
              raise ActiveRecord::Rollback
            end
          end
        end

        # 事务处理完成后，根据结果渲染响应
        if error_message
          render json: { error: error_message }, status: :unprocessable_entity
        else
          # 无论字段列表是否为空，如果没有出错就返回成功状态
          render json: {
            fields: @dynamic_table.reload.dynamic_fields,
            table_name: @dynamic_table.table_name,
            app_entity_id: @dynamic_table.app_entity_id
          }, status: :created
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
      @dynamic_table = DynamicTable.find_by(id: params[:dynamic_table_id])
      unless @dynamic_table
        render json: { error: "指定的动态表未找到" }, status: :not_found and return # 确保停止执行
      end
    end

    def create_new_field(field, dynamic_table, updated_or_created_fields)
      # 首先验证字段参数
      if field[:name].blank?
        raise StandardError, "字段名不能为空"
      end

      # 检查字段是否已经存在
      existing_field = dynamic_table.dynamic_fields.find_by(name: field[:name])
      if existing_field
        # 如果字段已存在，将其添加到更新列表中并返回
        Rails.logger.info "字段 #{field[:name]} 已存在，跳过创建"
        updated_or_created_fields << existing_field
        return
      end

      # 创建新字段
      new_field = dynamic_table.dynamic_fields.new(field)

      # 保存字段记录
      new_field.save!

      # 添加到物理表并处理错误
      result = DynamicTableService.add_field_to_physical_table(dynamic_table, new_field)

      # 检查结果并处理错误
      unless result && result[:success]
        # 删除刚创建的记录，因为物理表操作失败
        new_field.destroy

        error_msg = result && result[:error] ?
                    result[:error] :
                    "处理字段时发生意外情况"

        raise StandardError, error_msg
      end

      updated_or_created_fields << new_field
    end

    def update_existing_field(field, dynamic_table, updated_or_created_fields)
      # 查找现有字段
      existing_field = DynamicField.find(field[:id])

      # 字段名变更处理
      if existing_field.name != field[:name]
        begin
          DynamicTableService.rename_field_in_physical_table(dynamic_table, existing_field.name, field[:name])
        rescue StandardError => e
          # 包装异常以便事务回滚
          raise StandardError, "重命名字段失败: #{e.message}"
        end
      end

      # 字段类型变更处理
      if existing_field.field_type != field[:field_type]
        begin
          DynamicTableService.change_field_type(dynamic_table, field[:name], field[:field_type], existing_field.field_type)
        rescue StandardError => e
          # 包装异常
          raise StandardError, "更改字段类型失败: #{e.message}"
        end
      end

      # 唯一性约束变更处理
      if existing_field.unique != field[:unique]
        Rails.logger.info "更新字段唯一性约束: #{field[:name]} 为 #{field[:unique]}"
        table_name = DynamicTableService.physical_table_name(dynamic_table)

        result = if field[:unique]
          # 添加唯一约束
          DynamicTableService.add_unique_index(table_name, field[:name])
        else
          # 移除唯一约束
          DynamicTableService.remove_unique_index(table_name, field[:name])
        end

        unless result && result[:success]
          error_msg = result && result[:error] ? result[:error] : "更新唯一约束时发生未知错误"
          raise StandardError, error_msg
        end
      end

      # 更新字段记录
      existing_field.update!(field)
      updated_or_created_fields << existing_field
    end
  end
end
