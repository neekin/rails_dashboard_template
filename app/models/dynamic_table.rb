class DynamicTable < ApplicationRecord
  has_many :dynamic_fields, dependent: :destroy

  # 验证表名存在且格式正确
  validates :table_name, presence: true,
                        uniqueness: true,
                        length: { minimum: 1, maximum: 64 }

  # 自定义验证: 表名不能以数字开头
  validate :table_name_cannot_start_with_number

  private

  def table_name_cannot_start_with_number
    if table_name.present? && table_name.match(/\A\d/)
      errors.add(:table_name, "不能以数字开头")
    end
  end
end
