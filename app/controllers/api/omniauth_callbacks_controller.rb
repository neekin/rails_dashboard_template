module Api
  class OmniauthCallbacksController < ApplicationController # Or your API base controller
    include Authenticable # Include the concern for generate_tokens

    # Skip any CSRF protection for this controller as it handles external callbacks
    skip_before_action :verify_authenticity_token, raise: false, only: [ :callback, :failure ]


    def callback
      auth = request.env["omniauth.auth"]
      user = User.from_omniauth(auth)

      if user&.persisted?
        tokens = generate_tokens(user)
        # Redirect to frontend with tokens. Ensure FRONTEND_URL is set.
        frontend_url = ENV.fetch("FRONTEND_URL", "http://127.0.0.1:3000") # Provide a default
        redirect_to "#{frontend_url}/oauth-callback?access_token=#{tokens['access-token']}&client=#{tokens['client']}&uid=#{tokens['uid']}", allow_other_host: true
      else
        error_message = user&.errors&.full_messages&.join(", ") || "Could not sign in with #{auth.provider.titleize}."
        frontend_url = ENV.fetch("FRONTEND_URL", "http://127.0.0.1:3000")
        redirect_to "#{frontend_url}/login?error=omniauth_error&provider=#{auth.provider}&message=#{CGI.escape(error_message)}", allow_other_host: true
      end
    rescue => e
      Rails.logger.error "OmniAuth Callback Error: #{e.message} - Auth Data: #{auth.inspect}"
      frontend_url = ENV.fetch("FRONTEND_URL", "http://127.0.0.1:3000")
      redirect_to "#{frontend_url}/login?error=omniauth_exception&message=#{CGI.escape('An unexpected error occurred during authentication.')}", allow_other_host: true
    end

    def failure
      frontend_url = ENV.fetch("FRONTEND_URL", "http://127.0.0.1:3000")
      error_message = params[:message] || "Authentication failed."
      redirect_to "#{frontend_url}/login?error=omniauth_failure&message=#{CGI.escape(error_message)}", allow_other_host: true
    end
  end
end
