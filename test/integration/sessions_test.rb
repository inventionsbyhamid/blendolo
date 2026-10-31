require "test_helper"
require "support/account_helpers"
require "support/kit_helpers"

class SessionsTest < ActionDispatch::IntegrationTest
  include AccountHelpers
  include KitHelpers

  teardown { OmniAuth.config.mock_auth.delete(:google_oauth2) }

  test "signing in with Google makes the account, gives the free credits once and goes back where it started" do
    kit = make_kit
    get kit_look_path(kit, "red_lip")
    mock_google(uid: "g-rosa", name: "Rosa Diaz", email: "rosa@example.com")

    post "/auth/google_oauth2", params: { origin: kit_look_path(kit, "red_lip") }
    follow_redirect!
    assert_redirected_to kit_look_path(kit, "red_lip")
    follow_redirect!
    assert_select ".flash", "You're signed in, Rosa."

    user = User.sole
    assert_equal [ "google_oauth2", "g-rosa", "rosa@example.com", "Rosa Diaz" ], [ user.provider, user.uid, user.email, user.name ]
    assert_equal 2, Credits.balance(user)
    assert_equal user, kit.reload.user, "the guest kit on this device joins the account"

    delete sign_out_path
    sign_in_as(user)
    assert_redirected_to account_path
    assert_equal 2, Credits.balance(user), "the free credits come once"
  end

  test "a sign in never claims an example kit or another account's kit" do
    june = make_user
    junes = make_kit.tap { it.update!(user: june) }
    get kit_path(junes)

    sign_in_as(make_user)
    assert_equal june, junes.reload.user

    get kit_path(Examples.kit_for("rosa"))
    assert_nil Examples.kit_for("rosa").user
  end

  test "sign in only comes back to a page on this site" do
    sign_in_as(make_user, origin: "https://elsewhere.example/steal")
    assert_redirected_to account_path

    delete sign_out_path
    sign_in_as(make_user, origin: "//elsewhere.example/steal")
    assert_redirected_to account_path
  end

  test "sign in starts with a POST: a GET never reaches Google" do
    get "/auth/google_oauth2"
    assert_response :not_found
  end

  test "the sign in POST needs the form's authenticity token" do
    ActionController::Base.allow_forgery_protection = true
    mock_google

    post "/auth/google_oauth2"
    assert_redirected_to %r{/auth/failure}
    assert_equal 0, User.count

    get sign_in_path
    token = css_select("form[action='/auth/google_oauth2'] input[name=authenticity_token]").first["value"]
    post "/auth/google_oauth2", params: { authenticity_token: token }
    assert_redirected_to %r{/auth/google_oauth2/callback}
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "a failed sign in goes back to the button" do
    OmniAuth.config.mock_auth[:google_oauth2] = :access_denied
    post "/auth/google_oauth2"
    follow_redirect!
    assert_redirected_to %r{/auth/failure}
    follow_redirect!
    assert_redirected_to sign_in_path
    follow_redirect!
    assert_select ".flash", "Signing in didn't finish. Please try again."
    assert_equal 0, User.count
  end

  test "the session holds the user id in a fresh session, and sign out ends it and forgets the kit" do
    kit = make_kit
    get kit_path(kit)
    old_session = session.id

    sign_in_as(make_user)
    assert_not_equal old_session, session.id
    assert session[:user_id]
    assert cookies[ApplicationController::KIT_COOKIE].present?

    delete sign_out_path
    assert_redirected_to root_path
    assert_nil session[:user_id]
    assert cookies[ApplicationController::KIT_COOKIE].blank?
    get account_path
    assert_redirected_to sign_in_path(origin: account_path)
  end

  test "the sign in page shows the Google button, and a signed in person goes to the account" do
    get sign_in_path(origin: "/k/abc/looks")
    assert_response :success
    assert_select "form[action='/auth/google_oauth2'][data-turbo=false] button.btn--google", text: /Sign in with Google/
    assert_select "form[action='/auth/google_oauth2'] input[name=origin][value=?]", "/k/abc/looks"
    assert_select "meta[name=robots][content=?]", "noindex, nofollow"

    sign_in_as(make_user)
    get sign_in_path
    assert_redirected_to account_path
  end

  test "Google's code and state stay out of the log" do
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io))
    get "/auth/google_oauth2/callback?state=secret-state&code=secret-code"
  ensure
    Rails.logger = original
    assert_no_match(/secret-state|secret-code/, io.string)
  end
end
