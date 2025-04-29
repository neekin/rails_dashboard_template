# app/controllers/api/profiles_controller.rb
module Api
  class ProfilesController < ApiController
    before_action :authorize_access_request!

    def show
      render json: { user: user_info(current_user) }
    end

    private

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
end
