Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github, ENV.fetch("GITHUB_CLIENT_ID", "client"), ENV.fetch("GITHUB_CLIENT_SECRET", "secret"), scope: "user:email"
  provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"], scope: "email profile", access_type: "online", prompt: "select_account"

  # Define a common failure route
  on_failure { |env| Api::OmniauthCallbacksController.action(:failure).call(env) }
end

OmniAuth.config.allowed_request_methods = [ :post, :get ] # Allow GET for OAuth redirects
OmniAuth.config.silence_get_warning = true # Suppress GET warning if you keep it
