# Google sign in (AUTH_PROVIDER=google, the default and so far the only provider). A POST to /auth/google_oauth2 with
# the form's authenticity token (omniauth-rails_csrf_protection checks it; a GET is never accepted) sends the person
# to Google; Google's answer comes back to /auth/google_oauth2/callback, which OmniAuth checks (state, code exchange)
# before SessionsController#create sees it. Only the basic scopes, name, email and picture, which need no Google
# review. GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are required in production (lib/required_env.rb).
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"],
    scope: "email,profile", prompt: "select_account"
end

OmniAuth.config.logger = Rails.logger
# A failed sign in goes to /auth/failure in every environment (development would raise instead).
OmniAuth.config.on_failure = ->(env) { OmniAuth::FailureEndpoint.new(env).redirect_to_failure }
# Callback URLs come from the site's own address, never from a request's Host header.
OmniAuth.config.full_host = "https://#{Rails.application.config.x.canonical_host}" if Rails.env.production?
