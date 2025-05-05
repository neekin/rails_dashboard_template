module Api
  class DynamicFieldsController < AdminController
    before_action :validate_user_ownership!, only: [ :index, :create ]
    before_action :set_dynamic_table, only: [ :index, :create ]


    def index
      # table = DynamicTable.find(params[:dynamic_table_id])
      fields = @dynamic_table.dynamic_fields
      render json: { fields: fields, table_name: @dynamic_table.table_name }
    end

    # POST /api/dynamic_tables/:dynamic_table_id/dynamic_fields
    def create
      error_messages = []
      status_code = :created # Default to created
      final_error_message = nil # Initialize error message

      begin # Wrap transaction and subsequent checks in begin/rescue
        ActiveRecord::Base.transaction do
          # Process fields from params
          # Use strong parameters to permit expected attributes
          fields_params = params.permit(fields: [ :id, :name, :field_type, :required, :unique ]).fetch(:fields, [])

          # Keep track of field names to handle potential renames within the same request
          old_names = {}
          # Fetch existing fields once for efficient lookup
          current_fields = @dynamic_table.dynamic_fields.index_by(&:id)

          fields_params.each do |field_attributes|
            field_id = field_attributes[:id]&.to_i
            field = field_id ? current_fields[field_id] : nil
            new_field = nil # Initialize new_field for the 'else' block scope

            service_result = nil # To store result from DynamicTableService calls

            if field # --- Existing field: Update ---
              old_name = field.name # Store original name before assigning attributes
              field.assign_attributes(field_attributes.except(:id)) # Update metadata attributes

              if field.valid?
                # Save metadata changes *before* physical changes
                # Use save! to raise RecordInvalid on validation failure, caught by outer rescue
                field.save!

                # --- Handle physical table changes ---
                # 1. Rename column if name changed?
                if field.name_previously_changed?
                  # !! 安全性: 确保 new_name 已在模型层验证格式 !!
                  begin
                    DynamicTableService.rename_field_in_physical_table(@dynamic_table, old_name, field.name)
                    # Update old_names map *only on successful rename* for subsequent operations
                    old_names[field.id] = field.name
                  rescue => e # Catch specific errors if possible, e.g., StatementInvalid
                    error_messages << "重命名字段 '#{old_name}' 到 '#{field.name}' 失败: #{e.message}"
                    status_code = :unprocessable_entity
                    # Continue processing other fields, rollback will happen later
                  end
                end

                # 2. Change unique constraint if unique changed?
                # Check if unique actually changed and no previous error occurred
                if field.unique_previously_changed? && status_code != :unprocessable_entity
                  # Use potentially renamed field name for the service call
                  current_field_name = old_names[field.id] || field.name
                  service_result = DynamicTableService.change_field_unique_constraint(@dynamic_table, current_field_name, field.unique)
                  # Log service result for debugging
                  Rails.logger.info "[Controller Create] Service result for unique constraint change on '#{current_field_name}': #{service_result.inspect}"
                  # Check service_result below
                end

                # 3. Change type? (Add logic if needed)

              else # Metadata validation failed (field.valid? was false)
                error_messages << "字段 '#{field_attributes[:name] || old_name}' 更新失败: #{field.errors.full_messages.join(', ')}"
                status_code = :unprocessable_entity # Mark as error
              end

            else # --- New field: Create ---
              new_field = @dynamic_table.dynamic_fields.build(field_attributes)
              if new_field.valid?
                # Save metadata *before* physical changes
                new_field.save! # Raises RecordInvalid on failure
                # Add column to physical table
                service_result = DynamicTableService.add_field_to_physical_table(@dynamic_table, new_field)
                # Log service result for debugging
                Rails.logger.info "[Controller Create] Service result for add field '#{new_field.name}': #{service_result.inspect}"
                # Check service_result below
              else # Metadata validation failed (new_field.valid? was false)
                error_messages << "字段 '#{field_attributes[:name]}' 创建失败: #{new_field.errors.full_messages.join(', ')}"
                status_code = :unprocessable_entity # Mark as error
              end
            end

            # --- Check Service Result (from add_field or change_unique) ---
            Rails.logger.info "[Controller Create] Checking service_result: #{service_result.inspect}"
            # 首先检查 service_result 是否存在且失败
            if service_result && !service_result[:success]
              error_field_name = field ? (old_names[field.id] || field.name) : field_attributes[:name]
              error_messages << "处理字段 '#{error_field_name}' 时出错: #{service_result[:error]}"
              status_code = :unprocessable_entity # Mark as error
            # 然后检查 service_result 是否为 nil，但我们期望它执行了 service 调用
            elsif service_result.nil? && ((field&.unique_previously_changed?) || (!field && new_field&.persisted?)) && status_code != :unprocessable_entity
              error_field_name = field ? (old_names[field.id] || field.name) : field_attributes[:name]
              error_messages << "处理字段 '#{error_field_name}' 的物理表操作时发生意外情况，未能获取 Service 结果。"
              status_code = :unprocessable_entity
            end
          end # end fields_params.each

          # --- Final Check and Raise Rollback ---
          if status_code == :unprocessable_entity
            # Combine messages BEFORE raising rollback
            final_error_message = error_messages.join("; ")
            Rails.logger.info "[Controller Create] Raising Rollback due to errors: #{final_error_message}"
            # Raise Rollback - this will trigger DB rollback
            raise ActiveRecord::Rollback
          end

          # --- Success Path --- Render inside transaction
          Rails.logger.info "[Controller Create] Transaction successful. Rendering success response."
          render json: { table_name: @dynamic_table.table_name, fields: @dynamic_table.dynamic_fields.reload.as_json }, status: :created
          # Explicitly return to prevent fall-through
          return
        end # End ActiveRecord::Base.transaction

        # --- Check status code AFTER transaction block ---
        # This part will only be reached if the transaction block finished
        # without hitting the 'return' in the success path (i.e., if Rollback was raised)
        if status_code == :unprocessable_entity
          Rails.logger.warn "[Controller Create] Transaction rolled back. Rendering error response."
          render json: { error: final_error_message.presence || "处理字段时发生错误，操作已回滚。" }, status: :unprocessable_entity
        else
          # This case should ideally not be reached.
          Rails.logger.error "[Controller Create] Unexpected state after transaction block. Status code: #{status_code}"
          render json: { error: "处理完成，但状态未知。" }, status: :internal_server_error
        end

      rescue ActiveRecord::RecordInvalid => e # Catch validation errors during metadata save!
        Rails.logger.error "[Controller Create] Caught RecordInvalid: #{e.message}"
        render json: { error: "字段验证失败: #{e.record.errors.full_messages.join(', ')}" }, status: :unprocessable_entity
      # Removed the rescue ActiveRecord::Rollback block
      rescue => e # Catch any other unexpected errors
        Rails.logger.error "[Controller Create] Caught generic error: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: "处理字段时发生内部服务器错误: #{e.message}" }, status: :internal_server_error
      end # End begin/rescue
    end

    private

    def set_dynamic_table
      @dynamic_table = DynamicTable.find(params[:dynamic_table_id])
      # Add authorization check if needed: authorize! :manage, @dynamic_table
    rescue ActiveRecord::RecordNotFound
      render json: { error: "指定的动态表未找到" }, status: :not_found
    end

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
