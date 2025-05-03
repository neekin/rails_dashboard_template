class DynamicTable < ApplicationRecord
  belongs_to :app_entity
  has_many :dynamic_fields, dependent: :destroy

  # 修改唯一性验证规则，使表名在同一个 app_entity 下唯一
  validates :table_name, presence: true,
                         uniqueness: { scope: :app_entity_id, message: "在同一个应用下表名必须唯一" },
                         format: { without: /\A\d/, message: "不能以数字开头" }

  # 添加API标识符验证
  validates :api_identifier, uniqueness: { allow_blank: true },
            format: {
              with: /\A[a-z][a-z0-9_]*\z/,
              message: "只能包含小写字母、数字和下划线，且必须以字母开头",
              allow_blank: true
            }

  # 获取API路径
  def api_path
    "/api/v1/#{api_identifier.presence || table_name.downcase}"
  end

  # 序列化时添加API路径
  def as_json(options = {})
    super(options).merge(api_url: api_path)
  end
end
