class AdminController < ActionController::API
  private
  # 授权用户
  def authorize_user!
    unless @app_entity.user_id == current_user.id
      render json: { error: "无权限执行此操作" }, status: :forbidden
    end
  end

  def authorize_access_request!
    head :unauthorized unless current_user_from_access_token
  end

  def current_user
    @current_user ||= current_user_from_access_token
  end

  def current_user_from_access_token
    token = request.headers["Authorization"]&.split(" ")&.last
    payload = JsonWebToken.decode(token)
    User.find_by(id: payload[:user_id]) if payload
  rescue
    nil
  end

  def user_info(user)
    {
      id: user.id,
      username: user.username,
      email: user.email
    }
  end
end
