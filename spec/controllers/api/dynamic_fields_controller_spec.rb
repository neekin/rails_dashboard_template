# spec/controllers/api/dynamic_fields_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicFieldsController, type: :controller do
  include DynamicTableHelper

  before(:all) do
    # 创建一个默认用户
    @user = User.create!(
      username: 'test_user',
      password: 'password123',
      password_confirmation: 'password123'
    )

    # 创建测试用的AppEntity
    @app_entity = AppEntity.create!(
      name: '测试应用',
      description: '用于测试的应用',
      status: :active,
      user_id: @user.id
    )
  end

  after(:all) do
    # 清理测试数据
    User.destroy_all
    AppEntity.destroy_all
    DynamicTable.destroy_all
  end
  before do
    allow(controller).to receive(:current_user).and_return(@user)
    @table = DynamicTable.create(table_name: "测试表格", app_entity_id: @app_entity.id)
    @field = @table.dynamic_fields.create(name: "name", field_type: "string", required: true)

    # 确保物理表存在
    table_name = physical_table_name(@table)
    unless ActiveRecord::Base.connection.table_exists?(table_name)
      ActiveRecord::Base.connection.create_table(table_name) do |t|
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
      expect(json_response["table_name"]).to eq("测试表格")
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
      expect(json_response["fields"]).to be_an(Array)
      expect(json_response["fields"].size).to eq(2)

      # 验证字段是否创建
      @table.reload
      expect(@table.dynamic_fields.count).to eq(2)
      expect(@table.dynamic_fields.pluck(:name)).to include("name", "age")

      # 验证物理表是否更新
      table_name = physical_table_name(@table)
      expect(ActiveRecord::Base.connection.column_exists?(table_name, "age")).to be true
    end

    it "成功更新现有字段" do
      fields_attributes = [
        { id: @field.id, name: "full_name", field_type: "string", required: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }

      expect(response).to have_http_status(:created)

      # 验证字段是否更新
      @field.reload
      expect(@field.name).to eq("full_name")

      # 验证物理表是否更新
      table_name = physical_table_name(@table)
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
      # 添加新字段
      new_field = @table.dynamic_fields.create!(name: "new_field", field_type: "string", required: false)
      DynamicTableService.add_field_to_physical_table(@table, new_field)

      # 获取动态模型
      dynamic_model = DynamicTableService.get_dynamic_model(@table)

      # 验证新字段是否存在
      expect(dynamic_model.columns.map(&:name)).to include("new_field")
    end
  end
  describe "唯一索引功能" do
    it "成功创建带有唯一约束的字段" do
      fields_attributes = [
        { id: @field.id, name: "name", field_type: "string", required: true },
        { name: "email", field_type: "string", required: false, unique: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }
      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response["fields"]).to be_an(Array)
      expect(json_response["fields"].size).to eq(2)

      # 验证字段是否创建，并且唯一约束是否正确设置
      @table.reload
      email_field = @table.dynamic_fields.find_by(name: "email")
      expect(email_field).not_to be_nil
      expect(email_field.unique).to be true

      # 验证物理表是否更新并包含唯一索引
      table_name = physical_table_name(@table)

      # 检查 SQLite 中的索引信息
      index_query = "PRAGMA index_list(#{table_name})"
      indexes = ActiveRecord::Base.connection.select_all(index_query).to_a

      # 应该有一个名为 index_#{table_name}_on_email 的唯一索引
      email_index = indexes.find { |idx| idx["name"].include?("email") }
      expect(email_index).not_to be_nil
      expect(email_index["unique"]).to eq(1) # SQLite 中 1 表示唯一索引
    end

    it "成功更新字段添加唯一约束" do
      field = @table.dynamic_fields.create!(name: "username", field_type: "string", required: false, unique: false)
      table_name = physical_table_name(@table)
      unless ActiveRecord::Base.connection.column_exists?(table_name, "username")
        ActiveRecord::Base.connection.add_column(table_name, "username", :string)
      end
      # 更新字段，添加唯一约束
      fields_attributes = [
        { id: field.id, name: "username", field_type: "string", required: false, unique: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }

      expect(response).to have_http_status(:created)

      # 验证响应中字段唯一约束是否正确设置
      json_response = JSON.parse(response.body)
      expect(json_response["fields"]).to be_an(Array)
      updated_field = json_response["fields"].find { |f| f["name"] == "username" }
      expect(updated_field).not_to be_nil
      expect(updated_field["unique"]).to eq(true)

      # 验证数据库中字段唯一约束是否更新
      field.reload
      expect(field.unique).to be true
    end

    it "成功更新字段移除唯一约束" do
      # 先创建一个带唯一约束的字段
      field = @table.dynamic_fields.create!(name: "code", field_type: "string", required: false, unique: true)

      # 确保物理表中有该字段
      table_name = physical_table_name(@table)
      unless ActiveRecord::Base.connection.column_exists?(table_name, "code")
        Rails.logger.info "在表 #{table_name} 中添加 code 列"
        ActiveRecord::Base.connection.add_column(table_name, "code", :string)
      end

      # 添加唯一索引
      begin
        index_name = "index_#{table_name}_on_code"
        unless ActiveRecord::Base.connection.index_exists?(table_name, :code, name: index_name)
          Rails.logger.info "为 code 列添加唯一索引"
          ActiveRecord::Base.connection.add_index(table_name, :code, unique: true, name: index_name)
        end
      rescue => e
        puts "添加索引失败: #{e.message}"
      end

      # 更新字段，移除唯一约束
      fields_attributes = [
        { id: field.id, name: "code", field_type: "string", required: false, unique: false }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }

      expect(response).to have_http_status(:created)

      # 验证字段唯一约束是否移除
      field.reload
      expect(field.unique).to be false

      # 验证物理表中的唯一索引已移除
      index_query = "PRAGMA index_list(#{table_name})"
      indexes = ActiveRecord::Base.connection.select_all(index_query).to_a
      code_index = indexes.find { |idx| idx["name"].include?("code") }
      expect(code_index).to be_nil # 索引应被移除
    end

    it "当存在重复数据时添加唯一约束应失败" do
      # 创建一个不带唯一约束的字段
      field = @table.dynamic_fields.create!(name: "status", field_type: "string", required: false, unique: false)

      # 确保物理表中有该字段
      table_name = physical_table_name(@table)
      unless ActiveRecord::Base.connection.column_exists?(table_name, "status")
        Rails.logger.info "在表 #{table_name} 中添加 status 列"
        ActiveRecord::Base.connection.add_column(table_name, "status", :string)
      end

      # 在物理表中插入两条有相同 status 的数据
      ActiveRecord::Base.connection.execute(
        "INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户1', 'active', '#{Time.current}', '#{Time.current}')"
      )
      ActiveRecord::Base.connection.execute(
        "INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户2', 'active', '#{Time.current}', '#{Time.current}')"
      )

      # 尝试更新字段，添加唯一约束
      fields_attributes = [
        { id: field.id, name: "status", field_type: "string", required: false, unique: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }

      # --- 修复: 期望 422 和特定错误消息 ---
      # 应该失败，因为存在重复数据，控制器应返回 422
      expect(response).to have_http_status(:unprocessable_entity) # 期望 422
      json_response = JSON.parse(response.body)
      puts json_response # 打印实际错误以供调试
      # 检查 Service 返回的特定错误消息

      expect(json_response["error"]).to include("无法添加唯一约束")
      # --- 结束修复 ---

      # 验证字段唯一约束未被更新
      field.reload
      expect(field.unique).to be false
    end
  end
end
