class AppEntity < ApplicationRecord
  has_many :dynamic_tables, dependent: :destroy  # 注意此处改为复数形式
  belongs_to :user
  validates :name, presence: true
  enum :status, { active: 0, inactive: 1, pending: 2 }
end
