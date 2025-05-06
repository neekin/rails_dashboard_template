# spec/controllers/api/dynamic_tables_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicTablesController, type: :controller do
  before(:each) do
    # 使用 SecureRandom 为每个测试创建唯一的用户名和邮箱
    @user = User.create!(
      username: "test_user_#{SecureRandom.hex(4)}",
      email: "test_user_#{SecureRandom.hex(4)}@example.com",
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

    # 模拟认证
    allow_any_instance_of(Api::DynamicTablesController).to receive(:authorize_access_request!).and_return(true)

    # 模拟授权检查
    allow_any_instance_of(Api::DynamicTablesController).to receive(:set_and_authorize_target_app_entity_for_index_create).and_wrap_original do |original, *args|
      controller = args.first || original.receiver
      controller.instance_variable_set(:@app_entity, @app_entity)
      true # 返回 true 表示授权成功
    end

    allow_any_instance_of(Api::DynamicTablesController).to receive(:set_and_authorize_dynamic_table_and_app_entity).and_wrap_original do |original, *args|
      controller = args.first || original.receiver
      controller.instance_variable_set(:@dynamic_table, @table)
      controller.instance_variable_set(:@app_entity, @app_entity)
      true # 返回 true 表示授权成功
    end

    # 清理可能存在的动态表
    cleanup_dynamic_tables

    # 创建测试表
    unique_table_name = "测试表格"
    @table = DynamicTable.create!(
      table_name: unique_table_name,
      app_entity_id: @app_entity.id
    )
    @field = @table.dynamic_fields.create!(
      name: "name",
      field_type: "string",
      required: true
    )

    # 为初始测试表创建物理表
    ensure_physical_table_exists(@table)
  end
  def ensure_physical_table_exists(table)
    table_name = "dyn_#{table.id}"
    unless ActiveRecord::Base.connection.table_exists?(table_name)
      ActiveRecord::Base.connection.create_table(table_name) do |t|
        # 创建物理表中的字段
        table.dynamic_fields.each do |field|
          case field.field_type
          when "string"
            t.string field.name, null: !field.required
          when "integer"
            t.integer field.name, null: !field.required
            # 添加其他字段类型...
          end
        end
        t.timestamps
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

  before do
    # 模拟登录用户
    allow(controller).to receive(:current_user).and_return(@user)
    # 创建一个关联到AppEntity的测试表
    # @table = DynamicTable.create(
    #   table_name: "测试表格",
    #   app_entity_id: @app_entity.id
    # )
  end

  after(:all) do
    # 清理测试数据
    cleanup_dynamic_tables
  end

  describe "GET #index" do
    it "返回带分页的动态表列表" do
      # 再创建几个表以测试分页
      # table1 = DynamicTable.create(table_name: "测试表格", app_entity_id: @app_entity.id)
      table2 = DynamicTable.create(table_name: "测试表格2", app_entity_id: @app_entity.id)
      table3 = DynamicTable.create(table_name: "测试表格3", app_entity_id: @app_entity.id)

      # 确保为新创建的表创建物理表
      [  table2, table3 ].each do |table|
        ensure_physical_table_exists(table)
      end

      get :index, params: { appId: @app_entity.id }
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
      search_table = DynamicTable.create(table_name: "搜索测试", app_entity_id: @app_entity.id)
      ensure_physical_table_exists(search_table)

      get :index, params: { query: { table_name: "搜索" }.to_json, appId: @app_entity.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(1)
      expect(json_response["data"][0]["table_name"]).to eq("搜索测试")
      expect(json_response["pagination"]["total"]).to eq(1)
    end

    it "支持排序" do
      # 清除现有数据以便精确测试排序
      # DynamicTable.delete_all

      older_table = DynamicTable.create(table_name: "B表格", app_entity_id: @app_entity.id)
      newer_table = DynamicTable.create(table_name: "A表格", app_entity_id: @app_entity.id)
      ensure_physical_table_exists(older_table)
      ensure_physical_table_exists(newer_table)
      # 测试按表名升序排序
      get :index, params: { sortField: "table_name", sortOrder: "ascend", appId: @app_entity.id }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(3)
      expect(json_response["data"][0]["table_name"]).to eq("A表格")
      expect(json_response["data"][1]["table_name"]).to eq("B表格")

      # 测试按创建时间降序排序（默认行为）
      get :index, params: { appId: @app_entity.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(3)
      expect(json_response["data"][0]["id"]).to eq(newer_table.id)
      expect(json_response["data"][1]["id"]).to eq(older_table.id)
    end

    it "支持分页" do
      # 清除现有数据
      # DynamicTable.delete_all

      # 创建12个表
      12.times do |i|
        table = DynamicTable.create(table_name: "分页测试表#{i+1}", app_entity_id: @app_entity.id)
        ensure_physical_table_exists(table)
      end

      # 测试第一页，每页5条
      get :index, params: { current: 1, pageSize: 5, appId: @app_entity.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["data"].size).to eq(5)
      expect(json_response["pagination"]["current"]).to eq(1)
      expect(json_response["pagination"]["pageSize"]).to eq(5)
      expect(json_response["pagination"]["total"]).to eq(13)

      # 测试第二页
      get :index, params: { current: 2, pageSize: 5, appId: @app_entity.id }

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
      post :create, params: { table_name: "新表格", fields: fields_attributes, app_entity: @app_entity.id }

      expect(response).to have_http_status(:accepted) # 修改为期望 202 Accepted
      json_response = JSON.parse(response.body)
      expect(json_response["message"]).to include("表格创建请求已提交")
      expect(json_response["table_id"]).to be_present

      # 验证表记录是否创建
      table = DynamicTable.find(json_response["table_id"])
      expect(table.table_name).to eq("新表格")

      # 注释掉物理表验证，因为是异步创建的
      # table_name = "dyn_#{json_response['table_id']}"
      # expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be true

      # 验证字段是否创建
      expect(table.dynamic_fields.count).to eq(2)
      expect(table.dynamic_fields.pluck(:name)).to include("name", "age")

      # 手动创建物理表以便后续测试能够正常进行
      ensure_physical_table_exists(table)
    end

    it "表名为空时创建失败" do
      post :create, params: { table_name: "", fields: [], app_entity: @app_entity.id }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("不能为空")
    end

    it "表名以数字开头时创建失败" do
      post :create, params: { table_name: "1test", fields: [], app_entity: @app_entity.id }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("不能以数字开头")
    end

    it "表名已存在时创建失败" do
      unique_name = "test_table_#{Time.now.to_i}"
      table = DynamicTable.create!(table_name: unique_name, app_entity_id: @app_entity.id)
      ensure_physical_table_exists(table)

      post :create, params: { table_name: unique_name, fields: [], app_entity: @app_entity.id }
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
      get :show, params: { id: 999 }
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to include("表格不存在")
    end
  end

  it "成功更新动态表字段" do
    # 准备数据
    table = DynamicTable.create!(table_name: "test_table", app_entity_id: @app_entity.id)
    ensure_physical_table_exists(table)
    field = table.dynamic_fields.create!(name: "name", field_type: "string", required: true)

    # 确保物理表存在并正确设置
    table_name = "dyn_#{table.id}"

    # 先删除表如果存在，避免冲突
    if ActiveRecord::Base.connection.table_exists?(table_name)
      ActiveRecord::Base.connection.drop_table(table_name)
    end

    # 重新创建表
    ActiveRecord::Base.connection.create_table(table_name) do |t|
      t.string :name, null: false
      t.timestamps
    end

    # 更新字段
    updated_fields = [
      { id: field.id, name: "full_name", field_type: "string", required: true },
      { name: "age", field_type: "integer", required: false }
    ]

    # 使用 puts 打印更多调试信息
    puts "原始字段名: name, 新字段名: full_name"

    put :update, params: { id: table.id, fields: updated_fields }

    # 如果有错误，打印出来以便调试
    if response.status != 202
      puts "更新失败，错误信息: #{response.body}"
    end

    expect(response).to have_http_status(:accepted)
    json_response = JSON.parse(response.body)
    expect(json_response["message"]).to include("表格更新请求已提交")

    # 验证字段是否更新
    table.reload
    expect(table.dynamic_fields.count).to eq(2)
    expect(table.dynamic_fields.pluck(:name)).to include("full_name", "age")

    # 打印列名以便调试
    columns = ActiveRecord::Base.connection.columns(table_name).map(&:name)
    puts "物理表中的列: #{columns.join(', ')}"

    # 注释掉物理表的验证，因为这些更改是异步的
    # 验证物理表是否更新
    # expect(ActiveRecord::Base.connection.column_exists?(table_name, "full_name")).to be true
    # expect(ActiveRecord::Base.connection.column_exists?(table_name, "age")).to be true
    # expect(ActiveRecord::Base.connection.column_exists?(table_name, "name")).to be false
  end

  describe "DELETE #destroy" do
    it "成功删除动态表" do
      table = DynamicTable.create!(table_name: "待删除表格", app_entity_id: @app_entity.id)
      ensure_physical_table_exists(table)

      delete :destroy, params: { id: table.id }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["status"]).to eq("success")
      expect(DynamicTable.exists?(table.id)).to be false
      expect(ActiveRecord::Base.connection.table_exists?("dyn_#{table.id}")).to be false
    end

    it "表不存在时返回404" do
      delete :destroy, params: { id: 9999, appId: @app_entity.id }
      expect(response).to have_http_status(:not_found)
    end
  end
end
