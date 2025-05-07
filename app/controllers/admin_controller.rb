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
      email: user.email,
      avatar_url: user.avatar_url
    }
  end
  # 校验当前用户是否拥有指定的 AppEntity 和 DynamicTable
  def validate_user_ownership!
    dynamic_table = DynamicTable.find_by(id: params[:dynamic_table_id])
    unless dynamic_table
      Rails.logger.error "DynamicTable not found for id: #{params[:dynamic_table_id]}"
      render json: { error: "表格不存在" }, status: :not_found
      return
    end


    app_entity = dynamic_table.app_entity
    unless app_entity
      Rails.logger.error "AppEntity not found for DynamicTable id: #{dynamic_table.id}"
      render json: { error: "应用不存在" }, status: :not_found
      return
    end

    unless app_entity.user_id == current_user.id
      Rails.logger.error "Unauthorized access by user #{current_user.id} for AppEntity id: #{app_entity.id}"
      render json: { error: "您无权操作此表格所属的应用" }, status: :forbidden
      return
    end

    # 设置实例变量供后续方法使用
    @dynamic_table = dynamic_table
    @app_entity = app_entity
  end
end
