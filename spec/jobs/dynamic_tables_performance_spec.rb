require 'rails_helper'
require 'benchmark'

RSpec.describe "Api::DynamicTablesController End-to-End Performance", type: :request do
  include ActiveJob::TestHelper

  # --- Test Setup ---
  let!(:user) { User.create!(username: "req_perf_user_#{SecureRandom.hex(4)}", email: "req_perf_user_#{SecureRandom.hex(4)}@example.com", password: 'password123', password_confirmation: 'password123') }
  let!(:app_entity) { AppEntity.create!(name: "Request Perf App #{SecureRandom.hex(4)}", user: user) }

  # Assuming JWT authentication. Adjust if your auth is different.
  # Ensure you have a way to generate a valid token for the user.
  # This might involve a helper method or directly using your JWT library.
  let(:auth_headers) do
    # 发送登录请求
    # 确保 api_login_path 路由是可用的，并且参数与 SessionsController#login 期望的一致
    post api_login_path, params: { username: user.username, password: 'password123' }, as: :json

    # 从登录响应中提取 access-token
    access_token = response.headers['access-token']

    # 检查登录是否成功并且 token 是否存在
    unless response.status == 200 && access_token.present?
      raise "Login failed or access-token not found in response. Status: #{response.status}, Body: #{response.body}, Headers: #{response.headers.inspect}"
    end

    # 构建用于后续请求的认证头部
    {
      'Authorization' => "Bearer #{access_token}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  # --- Configurable Test Parameters ---
  let(:number_of_tables_to_create) { 5 } # START SMALL! Adjust as needed.
  let(:fields_per_table) { 2 }

  # --- Test Cleanup ---
  after(:each) do
    # Clean up DynamicTable metadata and their physical tables
    # Filter by app_entity_id and a naming convention to be safe
    DynamicTable.where(app_entity_id: app_entity.id)
                .where("table_name LIKE 'e2e_perf_table_%'")
                .find_each do |table|
      physical_table_name = "dyn_#{table.id}" # Or use DynamicTableService.physical_table_name(table)
      if ActiveRecord::Base.connection.table_exists?(physical_table_name)
        ActiveRecord::Base.connection.drop_table(physical_table_name, force: :cascade)
        Rails.logger.info "[Test Cleanup] Dropped physical table: #{physical_table_name}"
      end
      table.destroy # This should also destroy associated DynamicFields due to dependent: :destroy
      Rails.logger.info "[Test Cleanup] Destroyed DynamicTable metadata: #{table.id} (Name: #{table.table_name})"
    end

    # Clean up ActiveJob queues
    clear_enqueued_jobs
    clear_performed_jobs
  end

  # --- Performance Test ---
  describe 'POST /api/dynamic_tables end-to-end performance', :performance, :slow do
    it "measures time to create tables via controller, enqueue jobs, and execute jobs" do
      # Ensure ActiveJob uses the test adapter for this test
      ActiveJob::Base.queue_adapter = :test # Explicitly set for clarity

      # 1. Prepare Payloads for Controller Requests
      table_creation_payloads = []
      number_of_tables_to_create.times do |i|
        field_attributes = []
        fields_per_table.times do |j|
          field_attributes << {
            name: "field_#{j}_#{SecureRandom.hex(3)}",
            field_type: "string",
            required: false,
            unique: false
          }
        end
        # 修改 payload 结构
        table_creation_payloads << {
          table_name: "e2e_perf_table_#{i}_#{SecureRandom.hex(4)}",
          api_identifier: "e2e_api_#{i}",
          app_entity: app_entity.id, # app_entity_id 在顶层
          fields: field_attributes
          # 如果控制器还期望其他参数在顶层，也一并移出
          # 例如 webhook_url: "http://example.com/webhook"
        }
      end

      # 2. Measure Controller Processing and Job Enqueuing Time
      controller_and_enqueue_time = Benchmark.measure do
        table_creation_payloads.each do |payload|
          # Adjust the path if your routes are different
          # The `app_entity_id` might be part of the path or a param
          # Assuming app_entity_id is part of the payload for simplicity here
          puts "Creating table with payload: #{api_dynamic_tables_path}"
          post api_dynamic_tables_path, params: payload.to_json, headers: auth_headers
          puts "Response: #{response.body}"
          unless response.status == 202 # HTTP Status Accepted
            puts "Unexpected response status: #{response.status}"
            puts "Response body: #{response.body}"
          end
          expect(response).to have_http_status(:accepted), "Failed for payload: #{payload.inspect}. Response: #{response.body}"
        end
      end

      puts "\n--- Controller & Enqueue Performance ---"
      puts "Tables Requested: #{number_of_tables_to_create}"
      puts "Time for Controller Processing & Job Enqueuing (real): #{controller_and_enqueue_time.real.round(4)}s"

      expected_job_count = number_of_tables_to_create * (1 + fields_per_table) # 1 ensure_table_exists + N add_field jobs per table
      expect(enqueued_jobs.size).to eq(expected_job_count)

      # 3. Measure Job Execution Time
      # Store created table IDs for verification later
      created_table_ids = DynamicTable.where(app_entity_id: app_entity.id)
                                     .where("table_name LIKE 'e2e_perf_table_%'")
                                     .pluck(:id)

      job_execution_time = Benchmark.measure do
        perform_enqueued_jobs(queue: :ddl_operations) # Execute jobs from the specified queue
      end

      puts "\n--- Job Execution Performance ---"
      puts "Total DDL Jobs Processed: #{expected_job_count}"
      puts "Time for Job Execution (real): #{job_execution_time.real.round(4)}s"

      # 4. Verification (check if physical tables and columns were created)
      expect(ActiveRecord::Base.connection.transaction_open?).to be false # Ensure no lingering transactions

      created_table_ids.each do |table_id|
        table_metadata = DynamicTable.find_by(id: table_id)
        next unless table_metadata # Skip if metadata somehow wasn't found

        physical_table_name = "dyn_#{table_metadata.id}"
        expect(ActiveRecord::Base.connection.table_exists?(physical_table_name)).to be(true),
          "Physical table #{physical_table_name} (metadata ID: #{table_metadata.id}) was not created."

        table_metadata.dynamic_fields.each do |field|
          expect(ActiveRecord::Base.connection.column_exists?(physical_table_name, field.name)).to be(true),
            "Column #{field.name} in physical table #{physical_table_name} was not created."
        end
      end

      expect(enqueued_jobs.size).to eq(0) # All jobs should have been performed
    end
  end
end
