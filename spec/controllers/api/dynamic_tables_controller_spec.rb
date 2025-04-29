# spec/controllers/api/dynamic_tables_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicTablesController, type: :controller do
  before do
    @table = DynamicTable.create(table_name: "测试表格")
  end

  describe "GET #index" do
    it "返回带分页的动态表列表" do
      # 再创建几个表以测试分页
      DynamicTable.create(table_name: "测试表格2")
      DynamicTable.create(table_name: "测试表格3")

      get :index
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      # 检查响应结构
      expect(json_response).to be_a(Hash)
      expect(json_response).to have_key("data")
      expect(json_response).to have_key("pagination")

      # 检查数据内容 - 改为不依赖于特定排序顺序
      expect(json_response["data"]).to be_an(Array)
      expect(json_response["data"].size).to eq(3) # 默认每页10条，应返回所有3个表
      expect(json_response["data"].map { |t| t["table_name"] }).to include("测试表格", "测试表格2", "测试表格3")

      # 检查分页信息
      expect(json_response["pagination"]["current"]).to eq(1)
      expect(json_response["pagination"]["pageSize"]).to eq(10)
      expect(json_response["pagination"]["total"]).to eq(3)
    end

    it "支持搜索查询" do
      DynamicTable.create(table_name: "搜索测试")

      get :index, params: { query: { table_name: "搜索" }.to_json }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(1)
      expect(json_response["data"][0]["table_name"]).to eq("搜索测试")
      expect(json_response["pagination"]["total"]).to eq(1)
    end

    it "支持排序" do
      # 清除现有数据以便精确测试排序
      DynamicTable.delete_all

      older_table = DynamicTable.create(table_name: "B表格")
      newer_table = DynamicTable.create(table_name: "A表格")

      # 测试按表名升序排序
      get :index, params: { sortField: "table_name", sortOrder: "ascend" }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(2)
      expect(json_response["data"][0]["table_name"]).to eq("A表格")
      expect(json_response["data"][1]["table_name"]).to eq("B表格")

      # 测试按创建时间降序排序（默认行为）
      get :index

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(2)
      expect(json_response["data"][0]["id"]).to eq(newer_table.id)
      expect(json_response["data"][1]["id"]).to eq(older_table.id)
    end

    it "支持分页" do
      # 清除现有数据
      DynamicTable.delete_all

      # 创建12个表
      12.times do |i|
        DynamicTable.create(table_name: "分页测试表#{i+1}")
      end

      # 测试第一页，每页5条
      get :index, params: { current: 1, pageSize: 5 }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(5)
      expect(json_response["pagination"]["current"]).to eq(1)
      expect(json_response["pagination"]["pageSize"]).to eq(5)
      expect(json_response["pagination"]["total"]).to eq(12)

      # 测试第二页
      get :index, params: { current: 2, pageSize: 5 }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(5)
      expect(json_response["pagination"]["current"]).to eq(2)
    end
  end

  describe "POST #create" do
    it "成功创建动态表" do
      fields_attributes = [
        { name: "name", field_type: "string", required: true },
        { name: "age", field_type: "integer", required: false }
      ]

      post :create, params: { table_name: "新表格", fields: fields_attributes }

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response["table_name"]).to eq("新表格")

      # 验证物理表是否创建
      table_name = "dyn_#{json_response['id']}"
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be true

      # 验证字段是否创建
      table = DynamicTable.find(json_response["id"])
      expect(table.dynamic_fields.count).to eq(2)
      expect(table.dynamic_fields.pluck(:name)).to include("name", "age")
    end

    it "表名为空时创建失败" do
      post :create, params: { table_name: "", fields: [] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("不能为空")
    end

    it "表名以数字开头时创建失败" do
      post :create, params: { table_name: "1test", fields: [] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("不能以数字开头")
    end

    it "表名已存在时创建失败" do
      # 先创建一个表
      DynamicTable.create!(table_name: "test_table")

      # 尝试创建同名表
      post :create, params: { table_name: "test_table", fields: [] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("已存在")
    end
  end

  describe "GET #show" do
    it "返回指定的动态表" do
      get :show, params: { id: @table.id }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["id"]).to eq(@table.id)
      expect(json_response["table_name"]).to eq("测试表格")
    end

    it "指定的表不存在时返回404" do
      expect {
        get :show, params: { id: 999 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "成功更新动态表字段" do
    # 准备数据
    table = DynamicTable.create!(table_name: "test_table")
    field = table.dynamic_fields.create!(name: "name", field_type: "string", required: true)

    # 确保物理表存在
    table_name = "dyn_#{table.id}"
    unless ActiveRecord::Base.connection.table_exists?(table_name)
      ActiveRecord::Base.connection.create_table(table_name) do |t|
        t.string :name, null: false
        t.timestamps
      end
    end

    # 更新字段
    updated_fields = [
      { id: field.id, name: "full_name", field_type: "string", required: true },
      { name: "age", field_type: "integer", required: false }
    ]

    put :update, params: { id: table.id, fields: updated_fields }

    expect(response).to have_http_status(:ok)
    json_response = JSON.parse(response.body)
    expect(json_response["status"]).to eq("success")

    # 验证字段是否更新
    table.reload
    expect(table.dynamic_fields.count).to eq(2)
    expect(table.dynamic_fields.pluck(:name)).to include("full_name", "age")

    # 验证物理表是否更新
    expect(ActiveRecord::Base.connection.column_exists?(table_name, "full_name")).to be true
    expect(ActiveRecord::Base.connection.column_exists?(table_name, "age")).to be true
    expect(ActiveRecord::Base.connection.column_exists?(table_name, "name")).to be false
  end

  describe "DELETE #destroy" do
    it "成功删除动态表" do
      # 创建测试表格
      table = DynamicTable.create!(table_name: "待删除表格")
      field = table.dynamic_fields.create!(name: "test_field", field_type: "string", required: true)

      # 创建物理表
      table_name = "dyn_#{table.id}"
      ActiveRecord::Base.connection.create_table(table_name) do |t|
        t.string :test_field
        t.timestamps
      end

      # 确认物理表存在
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be true

      # 执行删除
      delete :destroy, params: { id: table.id }

      # 验证响应
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("success")

      # 验证表记录已删除
      expect(DynamicTable.exists?(table.id)).to be false

      # 验证物理表已删除
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be false
    end

    it "表不存在时返回404" do
      delete :destroy, params: { id: 9999 }
      expect(response).to have_http_status(:not_found)
    end
  end
end
