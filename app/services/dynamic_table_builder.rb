class DynamicTableBuilder
  def self.physical_table_name(table)
    "dyn_#{table.id}"
  end

  def self.create_physical_table(table)
    table_name = physical_table_name(table)
    return if ActiveRecord::Base.connection.table_exists?(table_name)

    fields = table.dynamic_fields

    ActiveRecord::Base.connection.create_table(table_name) do |t|
      fields.each do |field|
        if field.field_type.present? && field.name.present?
          t.send(field.field_type.to_sym, field.name, null: !field.required)
        else
          raise "Invalid field definition: #{field.inspect}"
        end
      end
      t.timestamps
    end
  end
end
