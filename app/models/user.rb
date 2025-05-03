class User < ApplicationRecord
  has_secure_password
  has_many :app_entities, dependent: :destroy
  validates :username, presence: true, uniqueness: true
  validates :email, uniqueness: true, allow_blank: true
  validates :password, length: { minimum: 6 }, if: -> { password.present? }
end
