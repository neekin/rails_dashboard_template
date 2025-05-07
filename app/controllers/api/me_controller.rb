module Api
    class MeController < AdminController # Assuming AdminController handles JWT authentication and provides current_user
      include Authenticable # For user_info method
      # Ensure your AdminController or a before_action here authenticates the user via JWT
      # For example: before_action :authenticate_request! (if that's your method)

      def show
        if current_user # current_user should be set by your authentication logic
          render json: user_info(current_user), status: :ok
        else
          render json: { error: "Not authenticated or user not found" }, status: :unauthorized
        end
      end
    end
end
