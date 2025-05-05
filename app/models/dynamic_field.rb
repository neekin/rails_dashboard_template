class DynamicField < ApplicationRecord
  belongs_to :dynamic_table

  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_]*\z/, message: "只能包含小写字母、数字和下划线，且必须以字母开头" },
                   length: { maximum: 60 }, # 根据数据库限制调整
                   uniqueness: { scope: :dynamic_table_id, message: "在同一表格内必须唯一" }

  validates :field_type, presence: true, inclusion: { in: %w[string integer boolean text date datetime decimal float file], message: "%{value} 不是有效的字段类型" }

  # 更新可用字段类型，增加file类型
  FIELD_TYPES = %w[string integer boolean text date datetime decimal float file].freeze
  validates :field_type, inclusion: { in: FIELD_TYPES }
  validates :unique, inclusion: { in: [ true, false ] }
end
