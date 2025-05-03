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
  end
end
