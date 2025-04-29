module DynamicTableHelper
  def physical_table_name(table)
    "dyn_#{table.id}"
  end
end
