# spec/helpers/dynamic_table_helper_spec.rb
require 'rails_helper'

RSpec.describe DynamicTableHelper, type: :helper do
  describe "#physical_table_name" do
    it "返回正确的物理表名" do
      table = DynamicTable.create(table_name: "测试表格")
      expect(helper.physical_table_name(table)).to eq("dyn_#{table.id}")
    end
  end

  describe "#sanitize_column_name" do
    it "移除列名中的不安全字符" do
      expect(helper.sanitize_column_name("my-column")).to eq("my_column")
      expect(helper.sanitize_column_name("my column")).to eq("my_column")
      expect(helper.sanitize_column_name("my.column")).to eq("my_column")
      expect(helper.sanitize_column_name("123column")).to eq("123column")
    end
  end

  describe "#sql_column_type" do
    it "返回正确的SQL列类型" do
      expect(helper.sql_column_type("string")).to eq("VARCHAR(255)")
      expect(helper.sql_column_type("integer")).to eq("INTEGER")
      expect(helper.sql_column_type("boolean")).to eq("BOOLEAN")
      expect(helper.sql_column_type("text")).to eq("TEXT")
      expect(helper.sql_column_type("date")).to eq("DATE")
      expect(helper.sql_column_type("datetime")).to eq("DATETIME")
      expect(helper.sql_column_type("decimal")).to eq("DECIMAL(10,2)")
      expect(helper.sql_column_type("float")).to eq("FLOAT")
      expect(helper.sql_column_type("unknown")).to eq("TEXT") # 未知类型默认为TEXT
    end
  end

  describe "#determine_default_value" do
    it "返回正确的默认值" do
      expect(helper.determine_default_value("string", "默认值")).to eq("默认值")
      expect(helper.determine_default_value("integer", 0)).to eq(0)
      expect(helper.determine_default_value("boolean", false)).to eq(false)
      expect(helper.determine_default_value("text", "默认文本")).to eq("默认文本")
      expect(helper.determine_default_value("date", Date.today)).to be_a(Date)
      expect(helper.determine_default_value("datetime", Time.now)).to be_a(Time)
      expect(helper.determine_default_value("decimal", 0.0)).to eq(0.0)
      expect(helper.determine_default_value("float", 0.0)).to eq(0.0)
      expect(helper.determine_default_value("unknown", nil)).to be_nil
    end
  end
end
