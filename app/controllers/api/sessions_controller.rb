module Api
  class SessionsController < AdminController
    include Authenticable # Add this
    before_action :authorize_refresh_by_access_request!, only: [ :refresh ]
    # If using skip_before_action :verify_authenticity_token for API controllers
    skip_before_action :verify_authenticity_token, raise: false, only: [ :login, :refresh, :logout ], if: -> { request.format.json? }

    def login
      user = User.find_by(username: params[:username])

      if user&.authenticate(params[:password])
        tokens = generate_tokens(user)
        set_auth_headers(tokens)
        render json: { user: user_info(user) }, status: :ok
      else
        render json: { error: "用户名或密码错误" }, status: :unauthorized
      end
    end

    def refresh
      user = current_user_from_refresh_token
      if user
        tokens = generate_tokens(user)
        set_auth_headers(tokens)
        render json: { user: user_info(user) }, status: :ok
      else
        render json: { error: "无效的刷新请求" }, status: :unauthorized
      end
    end

    def logout
      head :ok
    end

    private

    def generate_tokens(user)
      access_token = JsonWebToken.encode({ user_id: user.id }, 15.minutes.from_now)
      refresh_token = JsonWebToken.encode({ user_id: user.id, refresh: true }, 7.days.from_now)

      {
        "access-token" => access_token,
        "client" => refresh_token,
        "uid" => user.id.to_s
      }
    end

    def user_info(user)
      {
        id: user.id,
        username: user.username,
        email: user.email
      }
    end

    def current_user_from_refresh_token
      token = request.headers["client"] # Assuming 'client' header holds the refresh token
      return unless token.present?
      begin
        payload = JsonWebToken.decode(token)
        return unless payload && payload[:refresh] && payload[:user_id]
        User.find_by(id: payload[:user_id])
      rescue JWT::DecodeError => e
        Rails.logger.error "Refresh token decode error: #{e.message}"
        nil
      end
    end

    def authorize_refresh_by_access_request!
      head :unauthorized unless current_user_from_refresh_token
    end

    def set_auth_headers(tokens)
      tokens.each do |key, value|
        response.headers[key] = value
      end
    end
  end
end
