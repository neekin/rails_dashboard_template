# filepath: app/controllers/concerns/authenticable.rb
module Authenticable
  extend ActiveSupport::Concern

  private

  def generate_tokens(user)
    # Ensure JWT expiration times are sensible.
    # Access token: short-lived, e.g., 15-60 minutes
    # Refresh token: longer-lived, e.g., 7-30 days
    access_token_expiry = Rails.env.development? ? 1.day.from_now : 15.minutes.from_now # Longer for dev
    refresh_token_expiry = 7.days.from_now

    access_token = JsonWebToken.encode({ user_id: user.id }, access_token_expiry)
    refresh_token = JsonWebToken.encode({ user_id: user.id, refresh: true }, refresh_token_expiry)

    {
      "access-token" => access_token,
      "client" => refresh_token, # This is your refresh token
      "uid" => user.id.to_s      # User ID
    }
  end

  def user_info(user)
    {
      id: user.id,
      username: user.username,
      email: user.email,
      name: user.name,
      avatar_url: user.avatar_url,
      role: user.role, # 会返回 "user" 或 "admin"
      level: user.level  # 会返回 "free", "premium" 等
      # Add other relevant user fields
    }
  end
end
