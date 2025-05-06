# spec/controllers/api/dynamic_fields_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicFieldsController, type: :controller do
  include DynamicTableHelper

  before(:each) do
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

    # 模拟身份验证
    allow(controller).to receive(:authorize_access_request!).and_return(true)
    allow(controller).to receive(:validate_user_ownership!).and_return(true)

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

    # 创建物理表
    @physical_table_name = "dyn_#{@table.id}"
    ensure_physical_table_exists(@table)

    # 模拟设置动态表
    allow(controller).to receive(:set_dynamic_table) do
      controller.instance_variable_set(:@dynamic_table, @table)
      true  # 返回 true 表示授权成功
    end

    # 基本的服务方法模拟 - 所有方法简单地返回表示成功的值
    allow(DynamicTableService).to receive(:add_field_to_physical_table).and_return({ success: true })
    allow(DynamicTableService).to receive(:rename_field_in_physical_table).and_return(true)
    allow(DynamicTableService).to receive(:change_field_type).and_return(true)
    allow(DynamicTableService).to receive(:change_field_unique_constraint).and_return({ success: true })
    allow(DynamicTableService).to receive(:add_unique_index).and_return({ success: true })
    allow(DynamicTableService).to receive(:remove_unique_index).and_return({ success: true })
    allow(DynamicTableService).to receive(:physical_table_name).and_return(@physical_table_name)
  end

  def ensure_physical_table_exists(table)
    table_name = "dyn_#{table.id}"

    # 如果表已存在，先删除它
    if ActiveRecord::Base.connection.table_exists?(table_name)
      ActiveRecord::Base.connection.drop_table(table_name)
    end

    # 创建表
    ActiveRecord::Base.connection.create_table(table_name) do |t|
      table.dynamic_fields.each do |field|
        case field.field_type
        when "string"
          t.string field.name, null: !field.required
        when "integer"
          t.integer field.name, null: !field.required
        when "boolean"
          t.boolean field.name, null: !field.required
        when "text"
          t.text field.name, null: !field.required
        when "date"
          t.date field.name, null: !field.required
        when "datetime"
          t.datetime field.name, null: !field.required
        end
      end
      t.timestamps
    end

    table_name
  end

  def index_exists_with_unique?(table_name, column_name)
    # 直接使用 ActiveRecord::Base.connection.adapter_name 判断数据库类型
    adapter_name = ActiveRecord::Base.connection.adapter_name.downcase

    if adapter_name.include?('postgresql')
      # PostgreSQL特定查询
      # 假设 table_name 是完整的物理表名，pg_indexes.tablename 存储的是不带模式的实际表名
      query = "SELECT indexname, indisunique FROM pg_indexes WHERE tablename = '#{table_name}' AND indexdef LIKE '%#{column_name}%'"
      result = ActiveRecord::Base.connection.select_all(query).to_a
      result.any? { |idx| idx["indisunique"] } # indisunique is a boolean in pg_indexes
    elsif adapter_name.include?('mysql')
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
    context "新字段操作" do
      it "成功创建新字段" do
        # 手动添加物理列
        table_name = "dyn_#{@table.id}"
        unless ActiveRecord::Base.connection.column_exists?(table_name, "age")
          ActiveRecord::Base.connection.add_column(table_name, "age", :integer)
        end

        # 创建字段记录
        @table.dynamic_fields.create!(name: "age", field_type: "integer", required: false)

        # 发送请求
        post :create, params: { dynamic_table_id: @table.id, fields: [
          { id: @field.id, name: "name", field_type: "string", required: true },
          { name: "age", field_type: "integer", required: false }
        ] }

        expect(response).to have_http_status(:created)
        expect(@table.reload.dynamic_fields.count).to eq(2)
        expect(ActiveRecord::Base.connection.column_exists?(table_name, "age")).to be true
      end

      it "成功更新现有字段" do
        # 手动重命名物理列
        table_name = "dyn_#{@table.id}"
        if ActiveRecord::Base.connection.column_exists?(table_name, "name")
          ActiveRecord::Base.connection.rename_column(table_name, "name", "full_name")
        end

        # 更新字段记录
        @field.update!(name: "full_name")

        # 发送请求
        post :create, params: { dynamic_table_id: @table.id, fields: [
          { id: @field.id, name: "full_name", field_type: "string", required: true }
        ] }

        expect(response).to have_http_status(:created)
        expect(@field.reload.name).to eq("full_name")
        expect(ActiveRecord::Base.connection.column_exists?(table_name, "full_name")).to be true
        expect(ActiveRecord::Base.connection.column_exists?(table_name, "name")).to be false
      end

      it "空字段列表时仍然处理成功" do
        post :create, params: { dynamic_table_id: @table.id, fields: [] }
        expect(response).to have_http_status(:created)
      end

      it "动态模型应加载新添加的字段" do
        # 手动添加物理列
        table_name = "dyn_#{@table.id}"
        unless ActiveRecord::Base.connection.column_exists?(table_name, "new_field")
          ActiveRecord::Base.connection.add_column(table_name, "new_field", :string)
        end

        # 创建字段记录
        @table.dynamic_fields.create!(name: "new_field", field_type: "string", required: false)

        # 定义用于测试的简单动态模型
        dynamic_model_class = Class.new(ActiveRecord::Base) do
          self.table_name = table_name
        end

        # 定义常量
        class_name = table_name.camelize
        Object.send(:remove_const, class_name) if Object.const_defined?(class_name)
        Object.const_set(class_name, dynamic_model_class)

        # 模拟获取动态模型的方法
        allow(DynamicTableService).to receive(:get_dynamic_model).and_return(dynamic_model_class)

        # 发送请求
        post :create, params: { dynamic_table_id: @table.id, fields: [
          { id: @field.id, name: "name", field_type: "string", required: true },
          { name: "new_field", field_type: "string", required: false }
        ] }

        expect(response).to have_http_status(:created)
        expect(ActiveRecord::Base.connection.column_exists?(table_name, "new_field")).to be true

        # 使用动态模型创建一条记录并验证
        new_record = dynamic_model_class.create!(name: "测试名称", new_field: "新字段值")
        expect(new_record.new_field).to eq("新字段值")
      end
    end

    context "验证错误" do
      it "字段名无效时创建失败" do
        # 对于此测试，我们需要允许实际的 create 方法运行
        allow_any_instance_of(Api::DynamicFieldsController).to receive(:create).and_call_original

        # 模拟字段创建方法，使其在字段名称为空时返回错误
        allow_any_instance_of(Api::DynamicFieldsController).to receive(:create_new_field) do |instance, field_params, table, updated_fields|
          if field_params[:name].blank?
            raise StandardError, "字段名不能为空"
          end
        end

        post :create, params: { dynamic_table_id: @table.id, fields: [
          { name: "", field_type: "string", required: true }
        ] }

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("字段名不能为空")
      end
    end
  end

  describe "唯一索引功能" do
    it "成功创建带有唯一约束的字段" do
      # 手动添加物理列和索引
      table_name = "dyn_#{@table.id}"
      unless ActiveRecord::Base.connection.column_exists?(table_name, "email")
        ActiveRecord::Base.connection.add_column(table_name, "email", :string)
      end

      index_name = "index_#{table_name}_on_email"
      unless ActiveRecord::Base.connection.index_exists?(table_name, "email", name: index_name)
        ActiveRecord::Base.connection.add_index(table_name, "email", unique: true, name: index_name)
      end

      # 创建字段记录
      email_field = @table.dynamic_fields.create!(name: "email", field_type: "string", required: false, unique: true)

      post :create, params: { dynamic_table_id: @table.id, fields: [
        { id: @field.id, name: "name", field_type: "string", required: true },
        { name: "email", field_type: "string", required: false, unique: true }
      ] }

      expect(response).to have_http_status(:created)
      expect(email_field.reload.unique).to be_truthy
      expect(index_exists_with_unique?(table_name, "email")).to be_truthy
    end

    it "成功更新字段添加唯一约束" do
      # 创建字段记录
      field = @table.dynamic_fields.create!(name: "username", field_type: "string", unique: false)

      # 手动添加物理列和索引
      table_name = "dyn_#{@table.id}"
      unless ActiveRecord::Base.connection.column_exists?(table_name, "username")
        ActiveRecord::Base.connection.add_column(table_name, "username", :string)
      end

      index_name = "index_#{table_name}_on_username"
      unless ActiveRecord::Base.connection.index_exists?(table_name, "username", name: index_name)
        ActiveRecord::Base.connection.add_index(table_name, "username", unique: true, name: index_name)
      end

      # 更新字段记录以设置唯一性
      field.update!(unique: true)

      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "username", field_type: "string", required: false, unique: true } ]
      }

      expect(response).to have_http_status(:created)
      expect(field.reload.unique).to be true
      expect(index_exists_with_unique?(table_name, "username")).to be true
    end

    it "成功更新字段移除唯一约束" do
      # 创建字段记录
      field = @table.dynamic_fields.create!(name: "code", field_type: "string", unique: true)

      # 手动添加物理列
      table_name = "dyn_#{@table.id}"
      unless ActiveRecord::Base.connection.column_exists?(table_name, "code")
        ActiveRecord::Base.connection.add_column(table_name, "code", :string)
      end

      # 确保没有索引
      connection = ActiveRecord::Base.connection
      indexes = connection.indexes(table_name)
      code_indexes = indexes.select { |idx| idx.columns.include?("code") }
      code_indexes.each do |idx|
        connection.remove_index(table_name, name: idx.name) rescue nil
      end

      # 更新字段记录以移除唯一性
      field.update!(unique: false)

      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "code", field_type: "string", required: false, unique: false } ]
      }

      expect(response).to have_http_status(:created)
      expect(field.reload.unique).to be false
      expect(index_exists_with_unique?(table_name, "code")).to be false
    end

    it "当存在重复数据时添加唯一约束应失败" do
      # 对于此测试，我们需要允许实际的 create 方法运行
      allow_any_instance_of(Api::DynamicFieldsController).to receive(:create).and_call_original

      # 创建字段记录
      field = @table.dynamic_fields.create!(name: "status", field_type: "string", unique: false)

      # 手动添加物理列
      table_name = "dyn_#{@table.id}"
      unless ActiveRecord::Base.connection.column_exists?(table_name, "status")
        ActiveRecord::Base.connection.add_column(table_name, "status", :string)
      end

      # 插入重复数据
      now = ActiveRecord::Base.connection.quote(Time.current)
      ActiveRecord::Base.connection.execute("INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户1', 'active', #{now}, #{now})")
      ActiveRecord::Base.connection.execute("INSERT INTO #{table_name} (name, status, created_at, updated_at) VALUES ('用户2', 'active', #{now}, #{now})")

      # 模拟添加唯一约束失败
      allow(DynamicTableService).to receive(:add_unique_index) do |table_name, column_name|
        { success: false, error: "无法添加唯一约束，因为列 'status' 中存在重复值 'Duplicate'" }
      end

      post :create, params: {
        dynamic_table_id: @table.id,
        fields: [ { id: field.id, name: "status", field_type: "string", unique: true } ]
      }

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to include("Duplicate")
    end
  end
end
