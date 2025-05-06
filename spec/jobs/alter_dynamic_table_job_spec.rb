require 'rails_helper'
require 'benchmark'

RSpec.describe AlterDynamicTableJob, type: :job do
  include ActiveJob::TestHelper

  # 使用 let! 确保在测试开始前创建记录
  let!(:user) { User.create!(username: "perf_user_#{SecureRandom.hex(4)}", email: "perf_user_#{SecureRandom.hex(4)}@example.com", password: 'password123', password_confirmation: 'password123') }
  let!(:app_entity) { AppEntity.create!(name: "Perf App #{SecureRandom.hex(4)}", user: user) }

  # !!! 警告: 创建 2000 张表会非常耗时，建议从较小值开始测试 (例如 20 或 50) !!!
  # 您可以将此值调整为 2000，但请注意测试执行时间。
  let(:number_of_tables_to_create) { 2000 } # 用户可以按需调整此值
  let(:fields_per_table) { 2 } # 每张表创建的字段数

  # 清理测试后创建的动态表
  # 注意：这需要在所有测试（包括失败的测试）后运行
  # 如果测试因超时或其他原因中断，这些表可能不会被清理
  after(:each) do # 使用 :each 确保在每个 example 后尝试清理
    # 查找此测试可能创建的所有 DynamicTable 元数据
    DynamicTable.where(app_entity_id: app_entity.id).where("table_name LIKE 'perf_table_%'").find_each do |table|
      physical_table_name = "dyn_#{table.id}"
      if ActiveRecord::Base.connection.table_exists?(physical_table_name)
        ActiveRecord::Base.connection.drop_table(physical_table_name, force: :cascade)
        Rails.logger.info "[Test Cleanup] Dropped physical table: #{physical_table_name}"
      end
      # 删除元数据（如果上面的 drop_table 失败，元数据可能仍然存在）
      table.destroy
      Rails.logger.info "[Test Cleanup] Destroyed DynamicTable metadata: #{table.id}"
    end
  end

  describe 'performance for creating multiple tables via jobs', :performance, :slow do
    # 注意：这里修复了 it 描述字符串，使其不直接引用 let 变量
    it "measures the time to process jobs for creating a configurable number of tables" do
      # 确保 ActiveJob 使用测试适配器，以便我们可以控制作业执行
      # 这通常在 rails_helper.rb 中为测试环境设置
      expect(ActiveJob::Base.queue_adapter_name.to_s).to eq("test")

      tables_metadata = []

      # 1. 准备阶段：创建元数据并使作业入队
      # 这模拟了控制器中创建元数据并调用 perform_later 的过程
      number_of_tables_to_create.times do |i|
        # 创建 DynamicTable 元数据
        table = DynamicTable.create!(
          table_name: "perf_table_#{i}_#{SecureRandom.hex(4)}", # 保证表名唯一
          app_entity: app_entity
        )
        tables_metadata << table

        # 使 :ensure_table_exists 作业入队
        AlterDynamicTableJob.perform_later(table.id, :ensure_table_exists)

        # 为每个表创建字段元数据并使 :add_field 作业入队
        fields_per_table.times do |j|
          field = table.dynamic_fields.create!(
            name: "field_#{j}_#{SecureRandom.hex(3)}", # 保证字段名唯一
            field_type: "string"
          )
          AlterDynamicTableJob.perform_later(table.id, :add_field, { dynamic_field_id: field.id })
        end
      end

      # 验证作业已入队
      expected_job_count = number_of_tables_to_create * (1 + fields_per_table)
      expect(enqueued_jobs.size).to eq(expected_job_count)

      # 2. 执行阶段：执行所有入队的作业并测量时间
      # perform_enqueued_jobs 会同步执行队列中的作业
      measurement = nil
      begin
        measurement = Benchmark.measure do
          perform_enqueued_jobs(queue: :ddl_operations) # 仅执行指定队列的作业
        end
      rescue StandardError => e
        puts "错误发生在 perform_enqueued_jobs 期间: #{e.message}"
        puts e.backtrace.take(10).join("\n")
        raise # 重新抛出异常，让测试失败
      end

      # 输出测量结果
      puts "\n--- Performance Measurement ---"
      puts "Tables Created: #{number_of_tables_to_create}"
      puts "Fields per Table: #{fields_per_table}"
      puts "Total DDL Jobs Processed: #{expected_job_count}"
      puts "Time Taken (real): #{measurement.real.round(4)} seconds"
      puts "Time Taken (total): #{measurement.total.round(4)} seconds"
      puts "--- End Measurement ---\n"

      # 3. 验证阶段 (可选，但建议)
      # 检查物理表和列是否已创建
      tables_metadata.each do |table|
        physical_table_name = "dyn_#{table.id}"
        expect(ActiveRecord::Base.connection.table_exists?(physical_table_name)).to be(true),
          "物理表 #{physical_table_name} (元数据ID: #{table.id}) 未被创建。"

        table.dynamic_fields.each do |field|
          expect(ActiveRecord::Base.connection.column_exists?(physical_table_name, field.name)).to be(true),
            "列 #{field.name} 在物理表 #{physical_table_name} 中未被创建。"
        end
      end

      # 确保所有作业都已执行
      expect(enqueued_jobs.size).to eq(0)
    end
  end

  # 在每个测试后清理作业队列
  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end
end
