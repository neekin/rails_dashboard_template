class ApiKey < ApplicationRecord
  belongs_to :app_entity

  validates :apikey, presence: true, uniqueness: true
  validates :apisecret, presence: true

  before_validation :generate_keys, on: :create
  has_secure_token :apikey
  # def active?
  #   active && (expires_at.nil? || expires_at > Time.current)
  # end

  private

  def generate_keys
    self.apisecret ||= SecureRandom.hex(32)
  end
end
