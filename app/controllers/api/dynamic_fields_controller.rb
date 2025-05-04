module Api
  class DynamicFieldsController < AdminController
    before_action :validate_user_ownership!, only: [ :index, :create ]

    def index
      table = DynamicTable.find(params[:dynamic_table_id])
      fields = table.dynamic_fields
      render json: { fields: fields, table_name: table.table_name }
    end

    def create
      fields = field_params
      if fields.empty?
        Rails.logger.info "收到空字段列表，将删除表中的所有字段"
      end

      unless fields.is_a?(Array)
        render json: { error: "Invalid fields data" }, status: :unprocessable_entity
        return
      end

      updated_or_created_fields = []
      ActiveRecord::Base.transaction do
        dynamic_table = DynamicTable.find(params[:dynamic_table_id])
        existing_fields = dynamic_table.dynamic_fields

        # 确保物理表存在
        table_name = DynamicTableService.ensure_table_exists(dynamic_table)

        # 找出需要删除的字段
        incoming_field_ids = fields.map { |field| field[:id] }.compact
        fields_to_delete = existing_fields.where.not(id: incoming_field_ids)

        # 删除多余的字段
        fields_to_delete.each do |field|
          begin
            DynamicTableService.remove_field_from_physical_table(dynamic_table, field)
            field.destroy!
          rescue => e
            raise ActiveRecord::Rollback
          end
        end

        # 更新或创建字段
        fields.each do |field|
          if field[:id].present?
            update_existing_field(field, dynamic_table, updated_or_created_fields)
          else
            create_new_field(field, dynamic_table, updated_or_created_fields)
          end
        end
      end

      render json: { fields: updated_or_created_fields }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "字段操作失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: e.message }, status: :internal_server_error
    end

    private



    def update_existing_field(field, dynamic_table, updated_or_created_fields)
      existing_field = DynamicField.find(field[:id])

      if existing_field.name != field[:name]
        # 如果字段名称发生变化，更新物理表中的列名
        DynamicTableService.rename_field_in_physical_table(dynamic_table, existing_field.name, field[:name])
      end

      # 如果字段类型发生变化，需要处理SQLite的限制
      if existing_field.field_type != field[:field_type]
        DynamicTableService.change_field_type(dynamic_table, field[:name], field[:field_type], existing_field.field_type)
      end

      # 如果唯一性约束发生变化，更新物理表的唯一性约束
      if existing_field.unique != field[:unique]
        Rails.logger.info "更新字段唯一性约束: #{field[:name]} 为 #{field[:unique]}"
        result = DynamicTableService.change_field_unique_constraint(dynamic_table, field[:name], field[:unique])
        unless result[:success]
          Rails.logger.warn "唯一索引修改失败，恢复为原值: #{existing_field.unique}"
          raise StandardError, result[:error] # 使用标准错误抛出错误信息
        end
      end

      # 更新字段
      existing_field.update!(field)
      updated_or_created_fields << existing_field
    end

    def create_new_field(field, dynamic_table, updated_or_created_fields)
      created_field = DynamicField.create!(field)
      updated_or_created_fields << created_field

      # 添加字段到物理表
      DynamicTableService.add_field_to_physical_table(dynamic_table, created_field)
    end

    def field_params
      return [] if params[:fields].blank?

      params.require(:fields).map do |field|
        field.permit(:id, :name, :field_type, :required, :unique).merge(
          dynamic_table_id: params[:dynamic_table_id]
        ).to_h
      end
    rescue ActionController::ParameterMissing
      # 如果fields参数缺失，返回空数组
      []
    end
  end
end
