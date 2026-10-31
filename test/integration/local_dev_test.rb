require "test_helper"
require "open3"
require "support/copy_rules"
require "support/kit_helpers"
require "support/account_helpers"

# Local development without keys: "Sign in as a test person (local only)" and the test checkout. Both are off in
# tests and production; the tests that use them turn them on for the test and draw the routes again.
class LocalDevTest < ActionDispatch::IntegrationTest
  include KitHelpers
  include AccountHelpers

  teardown { Billing.provider = nil }

  test "tests have no local sign in and no test checkout" do
    assert_not Rails.configuration.x.local_sign_in
    assert_not Rails.configuration.x.local_billing
    assert_kind_of Billing::Dodo, Billing.provider

    get sign_in_path
    assert_select "button.btn--google", text: /Sign in with Google/
    assert_no_match(/test person/i, response.body)

    post "/local/sign_in"
    assert_response :not_found
    get "/local/checkout", params: { plan: "look_pack" }
    assert_response :not_found
    assert_equal 0, User.count
  end

  test "production has no local sign in and no test checkout, and pays with Dodo, even with no keys set" do
    script = <<~RUBY
      paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
      found = { sign_in: Rails.configuration.x.local_sign_in, billing: Rails.configuration.x.local_billing,
        routes: paths.grep(%r{\\A/local}), provider: Billing.provider.class.name, env: Rails.env }
      puts "LOCAL_DEV_CHECK \#{found.to_json}"
    RUBY
    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1", "GOOGLE_CLIENT_ID" => "",
            "GOOGLE_CLIENT_SECRET" => "", "DODO_API_KEY" => "", "R2_ACCOUNT_ID" => "test", "R2_ACCESS_KEY_ID" => "test",
            "R2_SECRET_ACCESS_KEY" => "test", "R2_BUCKET" => "test" }

    output, status = Open3.capture2e(env, "bin/rails", "runner", script, chdir: Rails.root.to_s)

    assert status.success?, output
    line = output.lines.find { |text| text.start_with?("LOCAL_DEV_CHECK ") }
    assert line, output
    assert_equal({ "sign_in" => false, "billing" => false, "routes" => [], "provider" => "Billing::Dodo", "env" => "production" },
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

  test "the test checkout adds a pack's credits through the webhook's own code" do
    with_local(:local_billing) do
      assert_kind_of Billing::LocalTest, Billing.provider
      user = make_user(credits: 0)
      sign_in_as(user)
      get pricing_path
      assert_select ".notice", count: 0

      post checkout_path, params: { plan: "look_pack" }
      assert_redirected_to %r{/local/checkout\?}
      assert_no_difference -> { Credits.balance(user) }, "nothing until Pay" do
        follow_redirect!
      end
      assert_response :success
      assert_select ".chip", "Local test"
      assert_select "h1", "Test checkout"
      assert_includes response.body, "Nothing is charged."
      assert_select "form[action='/local/checkout'] input[name=success_url][value=?]", billing_success_url(plan: "look_pack")
      assert_select "a[href=?]", pricing_url(anchor: "look-pack"), text: /Cancel/
      assert_empty CopyRules.problems(response.body)

      post "/local/checkout", params: { plan: "look_pack", success_url: billing_success_url(plan: "look_pack") }
      assert_redirected_to billing_success_url(plan: "look_pack")
      event = BillingEvent.sole
      assert_equal [ "local_test", "pack_paid", user, "look_pack", 16 ], [ event.provider, event.kind, event.user, event.plan, event.credits ]
      assert_equal 18, Credits.balance(user)

      follow_redirect!
      assert_select "[role=status]", "16 credits added. You have 18 credits."

      post "/local/checkout", params: { plan: "look_pack", success_url: "https://elsewhere.example/steal" }
      assert_redirected_to billing_success_path(plan: "look_pack")
      assert_equal 34, Credits.balance(user), "each test payment is its own payment"
    end
  end

  test "the test Clinic plan starts, shows in the portal and stops at the end of its month" do
    with_local(:local_billing) do
      user = make_user(credits: 0)
      sign_in_as(user)

      post "/local/checkout", params: { plan: "clinic" }
      assert user.reload.clinic?
      assert_equal 42, Credits.balance(user)

      post billing_portal_path
      assert_redirected_to %r{/local/portal\?}
      follow_redirect!
      assert_select "h1", "Test portal"
      assert_select "p", /Your Clinic plan is on\. It renews on/
      assert_empty CopyRules.problems(response.body)

      paid = BillingEvent.sole
      post "/local/portal"
      assert_redirected_to account_path
      assert_equal "Your Clinic plan won't renew. Nothing was charged.", flash[:notice]
      assert_equal "subscription_cancelled", BillingEvent.last.kind
      assert_nil BillingEvent.renewing_subscription_for(user)
      assert_in_delta paid.period_end, user.reload.clinic_until, 1.second
      assert user.clinic?, "on until its paid month ends"
    end
  end

  test "the test provider believes no webhook" do
    with_local(:local_billing) do
      post dodo_webhook_path, params: {}.to_json, headers: { "Content-Type" => "application/json" }
      assert_response :unauthorized
      assert_equal 0, BillingEvent.count
    end
  end

  test "the test checkout needs sign in" do
    with_local(:local_billing) do
      get "/local/checkout", params: { plan: "look_pack" }
      assert_redirected_to sign_in_path(origin: "/local/checkout?plan=look_pack")
    end
  end

  private
    # Turns local switches on for one test, as development does without keys, and draws the routes again.
    def with_local(*switches)
      switches.each { |switch| Rails.configuration.x.public_send(:"#{switch}=", true) }
      Billing.provider = nil
      Rails.application.reload_routes!
      yield
    ensure
      switches.each { |switch| Rails.configuration.x.public_send(:"#{switch}=", false) }
      Billing.provider = nil
      Rails.application.reload_routes!
    end
end
