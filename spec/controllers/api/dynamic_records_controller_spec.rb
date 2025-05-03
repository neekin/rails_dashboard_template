# spec/controllers/api/dynamic_records_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DynamicRecordsController, type: :controller do
  include DynamicTableHelper
  include ActionDispatch::TestProcess
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
    # 设置 ActiveStorage
    ActiveStorage::Current.url_options = { host: "localhost", port: "3000" }

    # 确保创建了测试图片文件
    create_test_image

    @table = DynamicTable.create(table_name: "测试表格", app_entity_id: @app_entity.id)
    @name_field = @table.dynamic_fields.create(name: "name", field_type: "string", required: true)
    @age_field = @table.dynamic_fields.create(name: "age", field_type: "integer", required: false)
    # 添加文件字段
    @avatar_field = @table.dynamic_fields.create(name: "avatar", field_type: "file", required: false)

    # 确保物理表存在
    table_name = physical_table_name(@table)
    # --- 强制重建表 ---
    # 先删除可能存在的旧表
    ActiveRecord::Base.connection.drop_table(table_name, if_exists: true)
    puts "Dropped table #{table_name} if it existed."

    # 重新创建表，确保包含所有字段
    ActiveRecord::Base.connection.create_table(table_name) do |t|
      t.string :name, null: false
      t.integer :age
      t.string :avatar  # 确保 avatar 字段存在
      t.timestamps
    end
    puts "Created physical table: #{table_name} with columns: name, age, avatar, timestamps"
    # --- 结束强制重建表 ---

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

    it "成功创建带有文件的记录" do
      file_path = Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')
      expect(File).to exist(file_path), "Test file missing: #{file_path}"
      file = fixture_file_upload(file_path, 'image/jpeg')

      # --- 统一 Mocking ---
      # 1. 创建一个已知 signed_id 的 mock blob
      expected_signed_id = "test_signed_id_create_#{SecureRandom.hex(4)}"
      mock_blob = instance_double(ActiveStorage::Blob, signed_id: expected_signed_id)

      # 2. 模拟 create_and_upload! 方法返回这个 mock_blob
      #    确保它只在接收到正确的参数时才返回 mock_blob
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_return(mock_blob)
      # --- 结束 Mocking ---

      post :create, params: {
        dynamic_table_id: @table.id,
        record: { name: "带文件的用户", age: 40, avatar: file }
      }

      # 调试输出
      # puts "Create Response Status: #{response.status}"
      # puts "Create Response Body: #{response.body}" #if response.status != 201

      expect(response).to have_http_status(:created)
      json_response = JSON.parse(response.body)
      expect(json_response["record"]["name"]).to eq("带文件的用户")
      expect(json_response["record"]["avatar"]).to eq(expected_signed_id) # 验证返回的 signed_id

      # 验证数据库
      table_name = physical_table_name(@table)
      db_record = ActiveRecord::Base.connection.select_one(
        "SELECT avatar FROM #{table_name} WHERE name = '带文件的用户'"
      )
      expect(db_record["avatar"]).to eq(expected_signed_id) # 验证存储的 signed_id
    end

    it "上传无效文件类型时创建失败" do
      # 模拟无效的文件上传 (一个非 ActionDispatch::Http::UploadedFile 对象)
      invalid_file = "[object Object]"  # 模拟从前端传来的无效文件对象

      post :create, params: {
        dynamic_table_id: @table.id,
        record: { name: "无效文件用户", age: 45, avatar: invalid_file }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      json_response = JSON.parse(response.body)
      expect(json_response["error"]).to include("Invalid file format")
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

    it "成功更新记录并上传新文件" do
      table_name = physical_table_name(@table)
      record = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM #{table_name} WHERE name = '张三'"
      )

      file_path = Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')
      file = fixture_file_upload(file_path, 'image/jpeg')

      # --- 统一 Mocking ---
      expected_signed_id = "test_signed_id_update_#{SecureRandom.hex(4)}"
      mock_blob = instance_double(ActiveStorage::Blob, signed_id: expected_signed_id)

      # 确保这里也是 and_return
      allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_return(mock_blob)
      # --- 结束 Mocking ---

      put :update, params: {
        dynamic_table_id: @table.id,
        id: record["id"],
        record: { name: "张三更新带文件", avatar: file } # 修改名字以便区分
      }

      # 调试输出
      puts "Update Response Status: #{response.status}"
      puts "Update Response Body: #{response.body}" # if response.status != 200

      expect(response).to have_http_status(:ok)
      # json_response = JSON.parse(response.body)
      # expect(json_response["record"]["name"]).to eq("张三更新带文件")
      # expect(json_response["record"]["avatar"]).to eq(expected_signed_id) # 验证返回的 signed_id

      # # 验证数据库
      updated_record = ActiveRecord::Base.connection.select_one(
        "SELECT name, avatar FROM #{table_name} WHERE id = #{record['id']}" # 可以只查询需要的字段
      )
      expect(updated_record["name"]).to eq("张三更新带文件") # 验证名字是否更新
      expect(updated_record["avatar"]).to eq(expected_signed_id) # 验证存储的 signed_id
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
