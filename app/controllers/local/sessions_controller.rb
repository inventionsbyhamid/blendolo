# POST /local/sign_in: "Sign in as a test person (local only)". Local development without Google keys only
# (config.x.local_sign_in; the route is drawn only then). One tap, no typing: it signs in one made-up person through
# SessionsController#create, the same code Google's callback reaches, so the free credits and this device's kit work
# just as they do after a real sign in.
module Local
  class SessionsController < ::SessionsController
    TEST_PERSON = { provider: "local", uid: "test-person",
                    info: { name: "Test person", email: "test.person@example.com" } }.freeze

    before_action { head :not_found unless Rails.configuration.x.local_sign_in }

    def create
      request.env["omniauth.auth"] = OmniAuth::AuthHash.new(TEST_PERSON)
      request.env["omniauth.origin"] = params[:origin]
      super
    end
  end
end
