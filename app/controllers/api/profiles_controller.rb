# app/controllers/api/profiles_controller.rb
module Api
  class ProfilesController < AdminController
    before_action :authorize_access_request!

    def show
      render json: { user: user_info(current_user) }
    end
  end
end
