class AlterDynamicTableJob < ApplicationJob
  queue_as :ddl_operations # 建议为 DDL 操作使用专门的队列

  # operation_type: :ensure_table_exists, :add_field, :remove_field, :rename_field, :change_type, :change_unique_constraint
  # payload: 包含操作所需的具体参数
  def perform(dynamic_table_id, operation_type, payload = {})
    table = DynamicTable.find_by(id: dynamic_table_id)
    unless table
      Rails.logger.error "AlterDynamicTableJob: DynamicTable with ID #{dynamic_table_id} not found. Aborting job."
      return # 如果表不存在，则不应重试
    end

    operation = operation_type.to_sym
    Rails.logger.info "AlterDynamicTableJob: Processing '#{operation}' for DynamicTable ID: #{table.id} (Name: #{table.table_name}). Payload: #{payload.inspect}"

    # 可以在这里添加一个状态更新，标记 DynamicTable 或 DynamicField 为处理中
    # table.update_column(:schema_status, :processing) if table.respond_to?(:schema_status)

    result = {} # 用于存储服务层返回的结果

    case operation
    when :ensure_table_exists
      # payload: {} (不需要额外参数)
      result = { success: !DynamicTableService.ensure_table_exists(table).nil? }
    when :add_field
      # payload: { dynamic_field_id: field.id }
      field = DynamicField.find_by(id: payload[:dynamic_field_id])
      if field
        result = DynamicTableService.add_field_to_physical_table(table, field)
      else
        Rails.logger.error "AlterDynamicTableJob: DynamicField with ID #{payload[:dynamic_field_id]} not found for :add_field operation on table #{table.id}."
        # 考虑是否需要将表或字段标记为失败状态
        return # 字段元数据不存在，无法继续
      end
    when :remove_field
      # payload: { dynamic_field_id: field.id }
      # 注意：此时 DynamicField 记录可能已经被删除，所以 payload 可能需要包含字段名
      # 或者，在控制器删除 DynamicField 记录之前派发作业
      field_to_remove_id = payload[:dynamic_field_id]
      field_name_to_remove = payload[:field_name] # 备用，如果记录已删除

      field_instance = DynamicField.with_deleted.find_by(id: field_to_remove_id) if field_to_remove_id # 如果使用 paranoia 或类似 gem
      field_instance ||= table.dynamic_fields.build(name: field_name_to_remove, field_type: "string") # 构造一个临时的，如果只有名字

      if field_instance && field_instance.name.present?
        result = { success: DynamicTableService.remove_field_from_physical_table(table, field_instance) }
      else
        Rails.logger.error "AlterDynamicTableJob: Could not determine field to remove for :remove_field operation on table #{table.id}. Payload: #{payload}"
        return
      end
    when :rename_field
      # payload: { dynamic_field_id: field.id, old_name: 'old_column_name', new_name: 'new_column_name' }
      # old_name 也可以从 field.name_before_last_save 获取，如果字段已更新
      field = DynamicField.find_by(id: payload[:dynamic_field_id])
      old_name = payload[:old_name]
      new_name = payload[:new_name]

      if field && old_name.present? && new_name.present?
        result = { success: DynamicTableService.rename_field_in_physical_table(table, old_name, new_name) }
      else
        Rails.logger.error "AlterDynamicTableJob: Missing data for :rename_field operation on table #{table.id}. Payload: #{payload}"
        return
      end
    when :change_type
      # payload: { dynamic_field_id: field.id, field_name: 'column_name', new_type_string: 'integer', old_type_string: 'string' }
      field = DynamicField.find_by(id: payload[:dynamic_field_id])
      field_name = payload[:field_name] || field&.name
      new_type = payload[:new_type_string]
      old_type = payload[:old_type_string]

      if field_name.present? && new_type.present? && old_type.present?
        result = { success: DynamicTableService.change_field_type(table, field_name, new_type, old_type) }
      else
        Rails.logger.error "AlterDynamicTableJob: Missing data for :change_type operation on table #{table.id}. Payload: #{payload}"
        return
      end
    when :change_unique_constraint
      # payload: { dynamic_field_id: field.id, field_name: 'column_name', add_unique: true/false }
      field = DynamicField.find_by(id: payload[:dynamic_field_id])
      field_name = payload[:field_name] || field&.name
      add_unique = payload[:add_unique]

      if field_name.present? && !add_unique.nil?
        result = DynamicTableService.change_field_unique_constraint(table, field_name, add_unique)
      else
        Rails.logger.error "AlterDynamicTableJob: Missing data for :change_unique_constraint operation on table #{table.id}. Payload: #{payload}"
        return
      end
    else
      Rails.logger.warn "AlterDynamicTableJob: Unknown operation_type: '#{operation}' for table #{table.id}. Job will not run."
      return # 未知操作，不重试
    end

    # 处理服务层返回的结果
    if result[:success]
      Rails.logger.info "AlterDynamicTableJob: Successfully processed '#{operation}' for DynamicTable ID: #{table.id}."
      # table.update_column(:schema_status, :applied) if table.respond_to?(:schema_status)
      # 可以在这里触发通知，例如通过 ActionCable 更新前端
    else
      error_message = result[:error] || "Unknown error during #{operation}."
      Rails.logger.error "AlterDynamicTableJob: Failed to process '#{operation}' for DynamicTable ID: #{table.id}. Error: #{error_message}"
      # table.update_column(:schema_status, :failed) if table.respond_to?(:schema_status)
      # table.update_column(:schema_error_message, error_message) if table.respond_to?(:schema_error_message)

      # 对于某些可重试的错误，可以不 raise，让 ActiveJob 的默认重试机制处理
      # 对于确定无法通过重试解决的错误（如数据验证错误），应该记录并可能通知，然后不再重试
      # 这里简单地重新抛出，让外部重试机制处理，但你可以根据错误类型决定是否 raise
      # 例如，如果错误是 "字段已存在" 或 "数据不兼容"，则不应重试
      non_retryable_errors = [ "无法添加唯一约束，因为列", "已存在于表", "数据不兼容" ]
      if non_retryable_errors.any? { |ne| error_message.include?(ne) }
        Rails.logger.warn "AlterDynamicTableJob: Non-retryable error for '#{operation}' on table #{table.id}. Error: #{error_message}. Job will not be retried further by re-raising."
        # 这里可以选择不 raise e，而是记录并完成作业
      else
        # 对于其他类型的错误，可以考虑让它重试
        raise StandardError, "Failed to process '#{operation}' for table #{table.id}: #{error_message}"
      end
    end

  rescue ActiveRecord::RecordNotFound => e
    # DynamicTable 或 DynamicField 记录在作业执行期间被删除
    Rails.logger.error "AlterDynamicTableJob: RecordNotFound during operation '#{operation_type}' for initial DynamicTable ID #{dynamic_table_id}. Error: #{e.message}. Job will not be retried."
    # 通常不应重试，因为依赖的记录已不存在
  rescue => e # 捕获其他所有标准错误
    Rails.logger.error "AlterDynamicTableJob: Unhandled error processing '#{operation_type}' for DynamicTable ID #{dynamic_table_id}. Error: #{e.class}: #{e.message}\nBacktrace:\n#{e.backtrace.join("\n")}"
    # 根据需要进行重试或错误处理
    # 重新抛出异常，让 Active Job 的重试机制（如 SolidQueue 的）处理
    # SolidQueue 会根据配置进行重试，并将最终失败的作业标记为失败
    raise e
  end
end
