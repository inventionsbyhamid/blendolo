require "test_helper"
require "open3"
require "support/copy_rules"
require "support/kit_helpers"
require "support/account_helpers"

# Local development without keys: "Sign in as a test person (local only)". It is off in tests and production; the
# tests that use it turn it on for the test and draw the routes again.
class LocalDevTest < ActionDispatch::IntegrationTest
  include KitHelpers
  include AccountHelpers

  test "tests have no local sign in" do
    assert_not Rails.configuration.x.local_sign_in

    get sign_in_path
    assert_select "button.btn--google", text: /Sign in with Google/
    assert_no_match(/test person/i, response.body)

    post "/local/sign_in"
    assert_response :not_found
    assert_equal 0, User.count
  end

  test "production has no local sign in, even with no keys set" do
    script = <<~RUBY
      paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
      found = { sign_in: Rails.configuration.x.local_sign_in, routes: paths.grep(%r{\\A/local}), env: Rails.env }
      puts "LOCAL_DEV_CHECK \#{found.to_json}"
    RUBY
    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1", "GOOGLE_CLIENT_ID" => "",
            "GOOGLE_CLIENT_SECRET" => "", "R2_ACCOUNT_ID" => "test", "R2_ACCESS_KEY_ID" => "test",
            "R2_SECRET_ACCESS_KEY" => "test", "R2_BUCKET" => "test" }

    output, status = Open3.capture2e(env, "bin/rails", "runner", script, chdir: Rails.root.to_s)

    assert status.success?, output
    line = output.lines.find { |text| text.start_with?("LOCAL_DEV_CHECK ") }
    assert line, output
    assert_equal({ "sign_in" => false, "routes" => [], "env" => "production" },
      JSON.parse(line.delete_prefix("LOCAL_DEV_CHECK ")))
  end

  test "the test person signs in with one tap, gets the free credits and keeps this device's kit" do
    with_local(:local_sign_in) do
      kit = make_kit
      get kit_look_path(kit, "red_lip")

      get sign_in_path(origin: kit_look_path(kit, "red_lip"))
      assert_select "form[action='/local/sign_in'][data-turbo=false] button.btn--primary", text: /Sign in as a test person \(local only\)/
      assert_select "form[action='/local/sign_in'] input[name=origin][value=?]", kit_look_path(kit, "red_lip")
      assert_select "button.btn--google", count: 0
      assert_empty CopyRules.problems(response.body)

      post "/local/sign_in", params: { origin: kit_look_path(kit, "red_lip") }
      assert_redirected_to kit_look_path(kit, "red_lip")
      follow_redirect!
      assert_select ".flash", "You're signed in, Test."

      user = User.sole
      assert_equal [ "local", "test-person", "Test person", "test.person@example.com" ], [ user.provider, user.uid, user.name, user.email ]
      assert_equal 2, Credits.balance(user), "the free credits"
      assert_equal user, kit.reload.user, "the kit on this device joins the account"

      delete sign_out_path
      post "/local/sign_in"
      assert_redirected_to account_path
      assert_equal [ user, 2 ], [ User.sole, Credits.balance(user) ], "the same person again, and the free credits once"
    end
  end

  private
    # Turns local switches on for one test, as development does without keys, and draws the routes again.
    def with_local(*switches)
      switches.each { |switch| Rails.configuration.x.public_send(:"#{switch}=", true) }
      Rails.application.reload_routes!
      yield
    ensure
      switches.each { |switch| Rails.configuration.x.public_send(:"#{switch}=", false) }
      Rails.application.reload_routes!
    end
end
