# spec/controllers/api/v1/dynamic_api_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::V1::DynamicApiController, type: :controller do
  include DynamicTableHelper
  include ActionDispatch::TestProcess

  before(:each) do
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

    # 创建API密钥
    @api_key = ApiKey.create!(
      remark: '测试API密钥',
      apikey: 'test_api_key',
      apisecret: 'test_api_secret',
      app_entity_id: @app_entity.id,
      active: true
    )
  end

  after(:all) do
    # 清理测试数据
    User.destroy_all
    AppEntity.destroy_all
    ApiKey.destroy_all
    DynamicTable.destroy_all
  end

  before do
    # 创建测试表
    @table = DynamicTable.create!(
      table_name: "测试表格",
      api_identifier: "test_table",
      app_entity_id: @app_entity.id
    )

    # 创建字段
    @name_field = @table.dynamic_fields.create!(name: "name", field_type: "string", required: true)
    @age_field = @table.dynamic_fields.create!(name: "age", field_type: "integer", required: false)

    # 确保物理表存在
    DynamicTableService.ensure_table_exists(@table)

    # 添加字段到物理表
    DynamicTableService.add_field_to_physical_table(@table, @name_field)
    DynamicTableService.add_field_to_physical_table(@table, @age_field)

    # 创建测试记录
    @model_class = DynamicTableService.get_dynamic_model(@table)
    @record = @model_class.create!(name: "张三", age: 25)
  end

  describe "认证功能" do
    it "使用有效的API密钥可以访问API" do
      request.headers["X-Api-Key"] = @api_key.apikey
      request.headers["X-Api-Secret"] = @api_key.apisecret

      get :index, params: { identifier: "test_table" }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key("data")
      expect(json_response).to have_key("pagination")
    end

    it "缺少API密钥时拒绝访问" do
      get :index, params: { identifier: "test_table" }

      expect(response).to have_http_status(:unauthorized)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to eq("缺少必要的认证参数 apikey 和 apisecret")
    end
  end

  describe "CRUD操作" do
    before do
      # 设置有效的认证头
      request.headers["X-Api-Key"] = @api_key.apikey
      request.headers["X-Api-Secret"] = @api_key.apisecret
    end

    it "获取记录列表" do
      get :index, params: { identifier: "test_table" }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["data"].length).to eq(1)
      expect(json_response["data"][0]["name"]).to eq("张三")
      expect(json_response["pagination"]["total"]).to eq(1)
    end

    it "获取单条记录" do
      get :show, params: { identifier: "test_table", id: @record.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["name"]).to eq("张三")
      expect(json_response["age"]).to eq(25)
    end

    it "创建新记录" do
      expect {
        post :create, params: {
          identifier: "test_table",
          name: "李四", age: 30
        }
      }.to change(@model_class, :count).by(1)

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response["name"]).to eq("李四")
    end

    it "更新记录" do
      put :update, params: {
        identifier: "test_table",
        id: @record.id,
        name: "张三改", age: 26
      }

      expect(response).to have_http_status(:ok)
      @record.reload
      expect(@record.name).to eq("张三改")
      expect(@record.age).to eq(26)
    end

    it "删除记录" do
      expect {
        delete :destroy, params: { identifier: "test_table", id: @record.id }
      }.to change(@model_class, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "文件字段更新功能" do
    before do
      request.headers["X-Api-Key"] = @api_key.apikey
      request.headers["X-Api-Secret"] = @api_key.apisecret

      # 添加文件字段到表格
      @avatar_field = @table.dynamic_fields.create!(name: "avatar", field_type: "file", required: false, unique: false)
      DynamicTableService.add_field_to_physical_table(@table, @avatar_field)

      # 重新加载动态模型
      @model_class = DynamicTableService.get_dynamic_model(@table)
    end

    it "通过API上传并更新avatar字段" do
      # 准备文件
      file = fixture_file_upload(Rails.root.join("spec", "fixtures", "files", "test_image.jpg"), "image/jpeg")

      # 发送更新请求
      put :update, params: {
        identifier: "test_table",
        id: @record.id,
        avatar: file
      }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      puts json_response.inspect
      expect(json_response).to have_key("avatar_url")
      expect(json_response["avatar_url"]).to be_present
      expect(json_response["avatar_url"]).to include("test_image.jpg")
    end
    it "通过API将avatar字段设置为空来删除文件" do
      # 先上传一个文件
      file = fixture_file_upload(Rails.root.join("spec", "fixtures", "files", "test_image.jpg"), "image/jpeg")
      put :update, params: { identifier: "test_table", id: @record.id, avatar: file  }
      expect(response).to have_http_status(:ok)
      # 重新加载记录以确认文件已附加
      @record.reload
      expect(@record.avatar).to be_present # 确认文件已存在
      put :update, params: {
        identifier: "test_table",
        id: @record.id,
        avatar: ""  # 或者用 nil: record: { avatar: nil }
      }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["avatar_url"]).to be_nil # 确认 URL 已移除
      # 确认记录中的字段也已清空
      @record.reload
      expect(@record.avatar).to be_nil
    end
  end
end
