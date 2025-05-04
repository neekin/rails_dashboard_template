class AppEntity < ApplicationRecord
  has_many :dynamic_tables, dependent: :destroy  # 注意此处改为复数形式
  belongs_to :user
  validates :name, presence: true
  validates :token, uniqueness: true # 添加唯一性校验
  enum :status, { active: 0, inactive: 1, pending: 2 }
  # has_secure_token :token
  # before_create :generate_token
  # before_save :generate_token
  # 设置默认状态为 active
  after_initialize :set_default_status, if: :new_record?
  has_many :api_keys, dependent: :destroy
  private

  def set_default_status
    self.status ||= :active
  end
end
