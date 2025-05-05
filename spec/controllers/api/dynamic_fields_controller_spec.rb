# spec/controllers/api/dynamic_fields_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicFieldsController, type: :controller do
  include DynamicTableHelper

  before(:all) do
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
  end

  after(:all) do
    User.destroy_all
    AppEntity.destroy_all
    DynamicTable.destroy_all
  end

  before do
    allow(controller).to receive(:current_user).and_return(@user)
    @table = DynamicTable.create!(table_name: "测试表格", app_entity_id: @app_entity.id)
    @field = @table.dynamic_fields.create!(name: "name", field_type: "string", required: true)

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
      expect(json_response["fields"].size).to eq(2)
      expect(@table.reload.dynamic_fields.count).to eq(2)

      table_name = physical_table_name(@table)
      expect(ActiveRecord::Base.connection.column_exists?(table_name, "age")).to be true
    end

    it "成功更新现有字段" do
      fields_attributes = [
        { id: @field.id, name: "full_name", field_type: "string", required: true }
      ]

      post :create, params: { dynamic_table_id: @table.id, fields: fields_attributes }

      expect(response).to have_http_status(:created)
      expect(@field.reload.name).to eq("full_name")

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
      new_field = @table.dynamic_fields.create!(name: "new_field", field_type: "string", required: false)
      DynamicTableService.add_field_to_physical_table(@table, new_field)
      dynamic_model = DynamicTableService.get_dynamic_model(@table)
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
      email_field = @table.reload.dynamic_fields.find_by(name: "email")
      expect(email_field.unique).to be true

      # table_name = physical_table_name(@table)
      # indexes = ActiveRecord::Base.connection.select_all("PRAGMA index_list(#{table_name})").to_a
      # email_index = indexes.find { |idx| idx["name"].include?("email") }
      # expect(email_index).not_to be_nil
      expect(index_exists?(table_name, "email")).to be true
      expect(email_index["unique"]).to eq(1)
    end

    it "成功更新字段添加唯一约束" do
      field = @table.dynamic_fields.create!(name: "username", field_type: "string", unique: false)
      table_name = physical_table_name(@table)
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
      table_name = physical_table_name(@table)
      ActiveRecord::Base.connection.add_column(table_name, "code", :string) unless ActiveRecord::Base.connection.column_exists?(table_name, "code")
      unless ActiveRecord::Base.connection.index_exists?(table_name, :code)
        ActiveRecord::Base.connection.add_index(table_name, :code, unique: true, name: "index_#{table_name}_on_code")
      end

      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "code", field_type: "string", required: false, unique: false } ]
      }

      expect(response).to have_http_status(:created)
      field.reload
      expect(field.unique).to be false

      indexes = ActiveRecord::Base.connection.select_all("PRAGMA index_list(#{table_name})").to_a
      code_index = indexes.find { |idx| idx["name"].include?("code") }
      expect(code_index).to be_nil
    end

    it "当存在重复数据时添加唯一约束应失败" do
      field = @table.dynamic_fields.create!(name: "status", field_type: "string", unique: false)
      table_name = physical_table_name(@table)
      ActiveRecord::Base.connection.add_column(table_name, "status", :string) unless ActiveRecord::Base.connection.column_exists?(table_name, "status")

      now = Time.current
      ActiveRecord::Base.connection.execute("INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户1', 'active', '#{now}', '#{now}')")
      ActiveRecord::Base.connection.execute("INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户2', 'active', '#{now}', '#{now}')")

      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "status", field_type: "string", unique: true } ]
      }

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to include("无法添加唯一约束")
      expect(field.reload.unique).to be false
    end
  end
end
