# spec/controllers/api/dynamic_fields_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicFieldsController, type: :controller do
  include DynamicTableHelper

  before(:each) do
    @user = User.create!(
      username: 'test_user',
      password: 'password123',
      password_confirmation: 'password123'
    )

    @app_entity = AppEntity.create!(
      name: '测试应用',
      description: '用于测试的应用',
      status: :active,
      user_id: @user.id
    )

    # 设置控制器使用当前用户
    allow(controller).to receive(:current_user).and_return(@user)

    # 清理可能存在的动态表
    cleanup_dynamic_tables

    # 创建测试表
    unique_table_name = "测试表格_#{Time.now.to_i}"
    @table = DynamicTable.create!(
      table_name: unique_table_name,
      app_entity_id: @app_entity.id
    )
    @field = @table.dynamic_fields.create!(
      name: "name",
      field_type: "string",
      required: true
    )
  end
  def index_exists_with_unique?(table_name, column_name)
    if DynamicTableService.postgresql?
      # PostgreSQL特定查询
      # 假设 table_name 是完整的物理表名，pg_indexes.tablename 存储的是不带模式的实际表名
      query = "SELECT indexname, indisunique FROM pg_indexes WHERE tablename = '#{table_name}' AND indexdef LIKE '%#{column_name}%'"
      result = ActiveRecord::Base.connection.select_all(query).to_a
      result.any? { |idx| idx["indisunique"] } # indisunique is a boolean in pg_indexes
    elsif DynamicTableService.mysql?
      # MySQL特定查询
      query = "SHOW INDEXES FROM #{table_name} WHERE Column_name = '#{column_name}' AND Non_unique = 0"
      result = ActiveRecord::Base.connection.select_all(query).to_a
      result.any?
    else
      # SQLite默认实现
      indexes = ActiveRecord::Base.connection.select_all("PRAGMA index_list(#{table_name})").to_a
      unique_indexes = indexes.select { |idx| idx["unique"] == 1 }
      unique_indexes.any? do |idx|
        index_info = ActiveRecord::Base.connection.select_all("PRAGMA index_info(#{idx['name']})").to_a
        index_info.any? { |col| col["name"] == column_name }
      end
    end
  end


  def cleanup_dynamic_tables
    # 先删除模型记录
    DynamicTable.destroy_all

    # 再删除物理表
    connection = ActiveRecord::Base.connection
    schema_prefix = "dyn_"
    tables_to_drop = connection.tables.select { |t| t.start_with?(schema_prefix) }

    tables_to_drop.each do |table_name|
      if connection.table_exists?(table_name)
        connection.drop_table(table_name, force: :cascade)
      end
    end
  end
  before(:each) do
    # Clean up any existing DynamicTable records to avoid uniqueness constraints
    DynamicTable.destroy_all

    connection = ActiveRecord::Base.connection
    schema_prefix = "dyn_"

    # Drop all physical dynamic tables
    tables_to_drop = connection.tables.select { |t| t.start_with?(schema_prefix) }

    tables_to_drop.each do |table_name|
      if connection.table_exists?(table_name)
        connection.drop_table(table_name, force: :cascade)
      end
    end

    # Set up controller with current user
    allow(controller).to receive(:current_user).and_return(@user)

    # Create a unique table name using a timestamp to avoid conflicts
    unique_table_name = "测试表格_#{Time.now.to_i}"

    # Create fresh test data
    @table = DynamicTable.create!(table_name: unique_table_name, app_entity_id: @app_entity.id)
    @field = @table.dynamic_fields.create!(name: "name", field_type: "string", required: true)

    # Create the physical table
    table_name = DynamicTableService.physical_table_name(@table)
    unless connection.table_exists?(table_name)
      connection.create_table(table_name) do |t|
        t.string :name, null: false
        t.timestamps
      end
    end
  end

  describe "GET #index" do
      it "返回指定表的所有字段" do
        get :index, params: { dynamic_table_id: @table.id }
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response["fields"]).to be_an(Array)
        expect(json_response["fields"].size).to eq(1)
        expect(json_response["fields"][0]["name"]).to eq("name")
        expect(json_response["table_name"]).to eq(@table.table_name)
      end
  end

  describe "POST #create" do
    it "成功创建新字段" do
      fields_attributes = [
        { id: @field.id, name: "name", field_type: "string", required: true },
        { name: "age", field_type: "integer", required: false }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }
      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response["fields"].size).to eq(2)
      expect(@table.reload.dynamic_fields.count).to eq(2)

      table_name = DynamicTableService.physical_table_name(@table)
      expect(ActiveRecord::Base.connection.column_exists?(table_name, "age")).to be true
    end

    it "成功更新现有字段" do
      fields_attributes = [
        { id: @field.id, name: "full_name", field_type: "string", required: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }


      expect(response).to have_http_status(:created)
      expect(@field.reload.name).to eq("full_name")

      table_name = DynamicTableService.physical_table_name(@table)
      expect(ActiveRecord::Base.connection.column_exists?(table_name, "full_name")).to be true
      expect(ActiveRecord::Base.connection.column_exists?(table_name, "name")).to be false
    end

    it "空字段列表时仍然处理成功" do
      post :create, params: { dynamic_table_id: @table.id, fields: [] }
      expect(response).to have_http_status(:created)
    end

    it "字段名无效时创建失败" do
      fields_attributes = [
        { name: "", field_type: "string", required: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "动态模型应加载新添加的字段" do
      # 使用控制器 API 创建新字段
      new_field_attributes = [
        { id: @field.id, name: "name", field_type: "string", required: true },
        { name: "new_field", field_type: "string", required: false }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: new_field_attributes }
      expect(response).to have_http_status(:created)

      # 验证物理表是否有该列
      physical_table_name = DynamicTableService.physical_table_name(@table)
      expect(ActiveRecord::Base.connection.column_exists?(physical_table_name, "new_field")).to be true

      # 验证动态模型能否识别该列
      dynamic_model = DynamicTableService.get_dynamic_model(@table)
      dynamic_model.table_name = physical_table_name

      # 使用动态模型创建一条记录以验证字段可用
      new_record = dynamic_model.create!(name: "测试名称", new_field: "新字段值")
      expect(new_record.new_field).to eq("新字段值")
    end
  end

  describe "唯一索引功能" do
    # it "成功创建带有唯一约束的字段" do
    #   fields_attributes = [
    #     { id: @field.id, name: "name", field_type: "string", required: true },
    #     { name: "email", field_type: "string", required: false, unique: true }
    #   ]

    #   post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }
    #   expect(response).to have_http_status(:created)
    #   email_field = @table.reload.dynamic_fields.find_by(name: "email")
    #   expect(email_field.unique).to be true

    #   # table_name = DynamicTableService.physical_table_name(@table)
    #   # indexes = ActiveRecord::Base.connection.select_all("PRAGMA index_list(#{table_name})").to_a
    #   # email_index = indexes.find { |idx| idx["name"].include?("email") }
    #   # expect(email_index).not_to be_nil
    #   expect(index_exists?(table_name, "email")).to be true
    #   expect(email_index["unique"]).to eq(1)
    # end
    it "成功创建带有唯一约束的字段" do
      fields_attributes = [
        { id: @field.id, name: "name", field_type: "string", required: true },
        { name: "email", field_type: "string", required: false, unique: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }
      expect(response).to have_http_status(:created)
      email_field = DynamicField.find_by(name: "email")
      expect(email_field.unique).to be_truthy

      table_name = DynamicTableService.physical_table_name(@table)
      expect(index_exists_with_unique?(table_name, "email")).to be_truthy
    end

    it "成功更新字段添加唯一约束" do
      field = @table.dynamic_fields.create!(name: "username", field_type: "string", unique: false)
      table_name = DynamicTableService.physical_table_name(@table)
      ActiveRecord::Base.connection.add_column(table_name, "username", :string) unless ActiveRecord::Base.connection.column_exists?(table_name, "username")

      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "username", field_type: "string", required: false, unique: true } ]
      }

      expect(response).to have_http_status(:created)
      field.reload
      expect(field.unique).to be true
    end

    it "成功更新字段移除唯一约束" do
      field = @table.dynamic_fields.create!(name: "code", field_type: "string", unique: true)
      table_name = DynamicTableService.physical_table_name(@table)

      # 确保字段存在
      unless ActiveRecord::Base.connection.column_exists?(table_name, "code")
        ActiveRecord::Base.connection.add_column(table_name, "code", :string)
      end

      # 先清除可能已存在的索引
      connection = ActiveRecord::Base.connection
      indexes = connection.indexes(table_name)
      code_indexes = indexes.select { |idx| idx.columns.include?("code") }
      code_indexes.each do |idx|
        connection.remove_index(table_name, name: idx.name) rescue nil
      end

      # 添加唯一索引
      index_name = "idx_unique_#{Time.now.to_i}_#{table_name}_code"
      connection.add_index(table_name, "code", unique: true, name: index_name)

      # 确认索引存在
      expect(index_exists_with_unique?(table_name, "code")).to be true
      field.update_column(:unique, true)

      # 发送请求移除唯一约束
      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "code", field_type: "string", required: false, unique: false } ]
      }

      # 验证结果
      expect(response).to have_http_status(:created)
      field.reload
      expect(field.unique).to be false

      # # 直接通过数据库查询验证
      # if DynamicTableService.mysql?
      #   query = "SHOW INDEXES FROM #{table_name} WHERE Column_name = 'code' AND Non_unique = 0"
      #   result = ActiveRecord::Base.connection.select_all(query).to_a
      #   puts "MySQL唯一索引查询结果: #{result.inspect}"
      #   expect(result).to be_empty
      # end
    end

    it "当存在重复数据时添加唯一约束应失败" do
      field = @table.dynamic_fields.create!(name: "status", field_type: "string", unique: false)
      table_name = DynamicTableService.physical_table_name(@table)
      ActiveRecord::Base.connection.add_column(table_name, "status", :string) unless ActiveRecord::Base.connection.column_exists?(table_name, "status")

      now = ActiveRecord::Base.connection.quote(Time.current)
      ActiveRecord::Base.connection.execute("INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户1', 'active', #{now}, #{now})")
      ActiveRecord::Base.connection.execute("INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户2', 'active', #{now}, #{now})")

      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "status", field_type: "string", unique: true } ]
      }
      # puts "Response body: #{response.body}"

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)

      # 修改预期消息匹配，可以使用更灵活的匹配方式
      expect(json_response["error"]).to include("Duplicate entry")
      # 或者更准确地匹配
      expect(json_response["error"]).to include("处理字段 'status' 失败")

      expect(field.reload.unique).to be false
    end
  end
end
# p
