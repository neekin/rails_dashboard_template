# spec/controllers/api/dynamic_records_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicRecordsController, type: :controller do
  include DynamicTableHelper

  before do
    @table = DynamicTable.create(table_name: "测试表格")
    @name_field = @table.dynamic_fields.create(name: "name", field_type: "string", required: true)
    @age_field = @table.dynamic_fields.create(name: "age", field_type: "integer", required: false)

    # 确保物理表存在
    table_name = physical_table_name(@table)
    unless ActiveRecord::Base.connection.table_exists?(table_name)
      ActiveRecord::Base.connection.create_table(table_name) do |t|
        t.string :name, null: false
        t.integer :age
        t.timestamps
      end
    end

    # 创建测试记录
    ActiveRecord::Base.connection.execute(
      "INSERT INTO #{table_name} (name, age, created_at, updated_at) VALUES ('张三', 25, '#{Time.current}', '#{Time.current}')"
    )
  end

  describe "GET #index" do
    it "返回指定表的所有记录" do
      get :index, params: { dynamic_table_id: @table.id }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["data"]).to be_an(Array)
      expect(json_response["data"].size).to eq(1)
      expect(json_response["data"][0]["name"]).to eq("张三")
      expect(json_response["data"][0]["age"]).to eq(25)
    end

    it "支持分页" do
      # 多添加10条记录
      table_name = physical_table_name(@table)
      10.times do |i|
        ActiveRecord::Base.connection.execute(
          "INSERT INTO #{table_name} (name, age, created_at, updated_at) VALUES ('用户#{i}', #{20+i}, '#{Time.current}', '#{Time.current}')"
        )
      end

      get :index, params: { dynamic_table_id: @table.id, current: 1, pageSize: 5 }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["data"]).to be_an(Array)
      expect(json_response["data"].size).to eq(5)
      expect(json_response["pagination"]["total"]).to eq(11)
    end

    it "支持过滤查询" do
      get :index, params: { dynamic_table_id: @table.id, query: { name: "张" }.to_json }
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response["data"]).to be_an(Array)
      expect(json_response["data"].size).to eq(1)
      expect(json_response["data"][0]["name"]).to eq("张三")
    end
  end

  describe "POST #create" do
    it "成功创建记录" do
      post :create, params: {
        dynamic_table_id: @table.id,
        record: { name: "李四", age: 30 }
      }

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response["record"]["name"]).to eq("李四")
      expect(json_response["record"]["age"]).to eq(30)

      # 验证记录是否创建
      table_name = physical_table_name(@table)
      record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE name = '李四'"
      )
      expect(record).not_to be_nil
      expect(record["age"]).to eq(30)
    end

    it "缺少必填字段时创建失败" do
      post :create, params: {
        dynamic_table_id: @table.id,
        record: { age: 30 } # 缺少必填的name字段
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "字段类型转换正确" do
      post :create, params: {
        dynamic_table_id: @table.id,
        record: { name: "王五", age: "35" } # age作为字符串传入
      }

      expect(response).to have_http_status(:created)

      # 验证记录是否创建，且类型是否正确
      table_name = physical_table_name(@table)
      record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE name = '王五'"
      )
      expect(record).not_to be_nil
      expect(record["age"]).to eq(35) # 应该被转换为整数
    end
  end

  describe "PUT #update" do
    it "成功更新记录" do
      # 先获取记录ID
      table_name = physical_table_name(@table)
      record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE name = '张三'"
      )

      put :update, params: {
        dynamic_table_id: @table.id,
        id: record["id"],
        record: { name: "张三更新", age: 26 }
      }

      expect(response).to have_http_status(:ok)

      # 验证记录是否更新
      updated_record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE id = #{record['id']}"
      )
      expect(updated_record["name"]).to eq("张三更新")
      expect(updated_record["age"]).to eq(26)
    end

    it "字段类型转换正确" do
      # 先获取记录ID
      table_name = physical_table_name(@table)
      record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE name = '张三'"
      )

      put :update, params: {
        dynamic_table_id: @table.id,
        id: record["id"],
        record: { age: "27" } # age作为字符串传入
      }

      expect(response).to have_http_status(:ok)

      # 验证记录是否更新，且类型是否正确
      updated_record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE id = #{record['id']}"
      )
      expect(updated_record["age"]).to eq(27) # 应该被转换为整数
    end
  end

  describe "DELETE #destroy" do
    it "成功删除记录" do
      # 先获取记录ID
      table_name = physical_table_name(@table)
      record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE name = '张三'"
      )

      delete :destroy, params: {
        dynamic_table_id: @table.id,
        id: record["id"]
      }

      expect(response).to have_http_status(:ok)

      # 验证记录是否删除
      count = ActiveRecord::Base.connection.select_value(
        "SELECT COUNT(*) FROM #{table_name} WHERE id = #{record['id']}"
      )
      expect(count).to eq(0)
    end
  end
end
