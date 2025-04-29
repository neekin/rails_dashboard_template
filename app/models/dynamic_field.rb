class DynamicField < ApplicationRecord
  belongs_to :dynamic_table

  validates :name, presence: true
  validates :field_type, inclusion: {
    in: %w[string integer boolean text date datetime decimal float],
    message: "%{value} is not a valid type"
  }
end
