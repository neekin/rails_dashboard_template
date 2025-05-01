class DynamicField < ApplicationRecord
  belongs_to :dynamic_table

  validates :name, presence: true
  validates :field_type, presence: true

  # 更新可用字段类型，增加file类型
  FIELD_TYPES = %w[string integer boolean text date datetime decimal float file].freeze
  validates :field_type, inclusion: { in: FIELD_TYPES }
end
