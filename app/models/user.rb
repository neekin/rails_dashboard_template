class User < ApplicationRecord
  has_secure_password
  has_many :app_entities, dependent: :destroy
  # 0: user, 1: admin
  enum :role, { user: 0, admin: 1 }
  enum :level, { free: 0, premium: 1, professional: 2, enterprise: 3 }

  validates :username, presence: true, uniqueness: { case_sensitive: false }, unless: :provider?
  validates :email, presence: true, uniqueness: { case_sensitive: false } # Email should always be unique
  validates :password, length: { minimum: 6 }, if: -> { password.present? || !provider? }
  # # 验证 role 和 level 是否在定义的枚举值中 (可选但推荐)
  validates :role, inclusion: { in: roles.keys }
  validates :level, inclusion: { in: levels.keys }



  def self.from_omniauth(auth)
    # Case 1: User already exists with this provider and UID
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    # Case 2: User exists with this email
    user_by_email = find_by(email: auth.info.email&.downcase)

    if user_by_email
      if user_by_email.provider.blank? # Link if it's a password-only account
        user_by_email.provider = auth.provider
        user_by_email.uid = auth.uid
        user_by_email.name = auth.info.name if auth.info.name.present? && user_by_email.name.blank?
        user_by_email.avatar_url = auth.info.image if auth.info.image.present? && user_by_email.avatar_url.blank?
        # If username was blank and provider is GitHub, try to set it from nickname
        if user_by_email.username.blank? && auth.provider == "github" && auth.info.nickname.present?
          user_by_email.username = auth.info.nickname
        end
        user_by_email.save
        user_by_email
      else
        # Email is associated with another OAuth account or a conflicting scenario.
        u = User.new(email: auth.info.email&.downcase)
        u.errors.add(:base, "此电子邮件已与其他登录方法关联或无法链接。")
        u # Unpersisted user with errors
      end
    else
      # Case 3: Create a new user
      new_user = User.new(
        provider: auth.provider,
        uid: auth.uid,
        email: auth.info.email&.downcase,
        name: auth.info.name, # Store full name in 'name' field
        avatar_url: auth.info.image,
        password: SecureRandom.hex(15) # Required by has_secure_password
      )

      # Assign username based on provider or generate if needed
      if auth.provider == "github" && auth.info.nickname.present?
        new_user.username = auth.info.nickname
      end

      # If username is still blank (e.g., for Google or if GitHub nickname was blank)
      # AND the database column 'username' requires a value (is NOT NULL)
      if new_user.username.blank? && User.columns_hash["username"].null == false
        # Generate a username, e.g., from email prefix or parameterized name
        base_username = auth.info.email&.split("@")&.first || auth.info.name&.parameterize || "user"
        candidate_username = base_username.slice(0, 20) # Limit length

        # Ensure uniqueness
        count = 0
        temp_username = candidate_username
        while User.exists?(username: temp_username)
          count += 1
          temp_username = "#{candidate_username.slice(0, 20 - (count.to_s.length + 1))}#{count}"
        end
        new_user.username = temp_username
      end

      # If after all attempts, username is blank AND model validation (not DB) requires it
      # (This check is mostly redundant if DB requires it, but good for clarity)
      # The `unless: :provider?` on validation means this won't be an issue for OAuth users
      # as long as `provider` is set.

      new_user.save # save will now use the assigned or generated username
      new_user # This user object will have errors if save failed (e.g., email uniqueness)
    end
  end

  def provider?
    provider.present?
  end
end
