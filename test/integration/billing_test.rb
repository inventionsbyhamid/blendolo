require "test_helper"
require "support/copy_rules"
require "support/kit_helpers"
require "support/account_helpers"
require "support/dodo_webhooks"

# Pricing, checkout, the page after paying, "Manage", the legal pages and the clinic's client list.
class BillingTest < ActionDispatch::IntegrationTest
  include KitHelpers
  include AccountHelpers
  include DodoWebhooks

  CHECKOUT = "https://test.checkout.dodopayments.com/session/cks_test_1".freeze

  setup { Billing.provider = dodo_provider }
  teardown { Billing.provider = nil }

  test "pricing is a public search page with three plans" do
    get pricing_path

    assert_response :success
    assert_select "title", "Pricing | Blendolo"
    assert_select "meta[name=description][content^='Blendolo is free to try.']"
    assert_select "link[rel=canonical][href='https://blendolo.dijmo.com/pricing']"
    assert_select "meta[name=robots]", count: 0
    assert_select "h1", "Free to try. Credits for your own face."
    assert_select ".plans > li", 3
    assert_select "#free .plan__price", "$0"
    assert_select "#look-pack .plan__price", /\$7\.99\s+once/
    assert_select "#clinic .plan__price", /\$19\s+a month/
    assert_select "#look-pack .plan__credits", /16 credits: 8 looks on your face/
    assert_select "#clinic .plan__credits", /40 credits every month/
    assert_select "#free .plan__credits", /2 credits when you sign in with Google/
    assert_includes response.body, "Step cards, your routine, the shopping list and sharing are always free."
    assert_select "h2", "What is a credit?"
    assert_select "form[action='#{checkout_path}'][data-turbo=false] input[name=plan][value=look_pack]"
    assert_select "form[action='#{checkout_path}'] input[name=plan][value=clinic]"
    assert_select "a[href='#{terms_path}']"
    assert_select "a[href='#{refunds_path}']"
    assert_empty CopyRules.problems(response.body)
  end

  test "pricing says when payments are in test mode" do
    get pricing_path
    assert_select ".notice", /Payments are in test mode\. Use a test card\./

    Billing.provider = dodo_provider(environment: "live_mode")
    get pricing_path
    assert_select ".notice", count: 0
  end

  test "terms and refunds name the merchant of record and the refund window" do
    get terms_path
    assert_response :success
    assert_select "title", "Terms | Blendolo"
    assert_includes response.body, "Dodo Payments is the merchant of record"
    assert_empty CopyRules.problems(response.body)

    get refunds_path
    assert_response :success
    assert_includes response.body, "within 14 days"
    assert_empty CopyRules.problems(response.body)
    assert_select "footer a[href='#{terms_path}']"
    assert_select "footer a[href='#{refunds_path}']"
    assert_select "footer a[href='#{pricing_path}']"

    get sitemap_path
    [ pricing_path, terms_path, refunds_path ].each { |path| assert_includes response.body, "https://blendolo.dijmo.com#{path}<" }
  end

  test "buying needs sign in first, then comes back to the plan" do
    post checkout_path, params: { plan: "look_pack" }

    assert_redirected_to sign_in_path(origin: "/pricing#look-pack")
  end

  test "buying makes the account's own customer once, then a checkout for it with our reference" do
    user = make_user(credits: 0, email: "rosa@example.com")
    sign_in_as(user)
    customer = stub_request(:post, "#{API}/customers").with(body: hash_including("email" => "rosa@example.com"))
      .to_return(status: 200, headers: JSON_HEADERS, body: customer_json("cus_rosa").to_json)
    checkout = stub_request(:post, "#{API}/checkouts").with { |request|
      body = JSON.parse(request.body)
      body["customer"] == { "customer_id" => "cus_rosa" } && Checkout.exists?(token: body["metadata"]["ref"], user:) &&
        body["feature_flags"]["allow_customer_editing_email"] == false
    }.to_return(status: 200, headers: JSON_HEADERS, body: { session_id: "cks_test_1", checkout_url: CHECKOUT }.to_json)

    assert_no_difference -> { Credits.balance(user) }, "credits come from the webhook, not the redirect" do
      post checkout_path, params: { plan: "look_pack" }
      post checkout_path, params: { plan: "look_pack" }
    end

    assert_redirected_to CHECKOUT
    assert_requested customer, times: 1
    assert_requested checkout, times: 2
    assert_equal "cus_rosa", user.reload.billing_customer_id
    assert_equal [ "look_pack", "pending", user ] * 2, Checkout.order(:id).flat_map { [ it.plan, it.status, it.user ] }
  end

  test "an unknown plan, or a provider that fails, goes back to pricing" do
    user = make_user
    user.update!(billing_customer_id: "cus_fail")
    sign_in_as(user)

    post checkout_path, params: { plan: "gold" }
    assert_redirected_to pricing_path

    stub_request(:post, "#{API}/checkouts").to_return(status: 500, body: "{}")
    post checkout_path, params: { plan: "look_pack" }
    assert_redirected_to pricing_path
    assert_equal "Payments aren't working right now, so nothing was charged. Please try again in a few minutes.", flash[:notice]
    assert_empty Checkout.all, "a checkout the provider never made is forgotten"
  end

  test "a clinic already on isn't sold twice" do
    user = make_user
    user.update!(clinic_until: 1.month.from_now)
    sign_in_as(user)

    post checkout_path, params: { plan: "clinic" }

    assert_redirected_to clinic_path
  end

  test "a standing Clinic subscription, or one being paid, never starts a second" do
    user = make_user
    sign_in_as(user)
    checkout = checkout_for(user, :clinic)

    post checkout_path, params: { plan: "clinic" }
    assert_redirected_to checkout.url, "an unfinished Clinic checkout from the last 30 minutes is picked up again"

    travel 31.minutes do
      receive_dodo(dodo_body("subscription_active", checkout:, next_billing_date: 1.month.from_now.utc.iso8601), id: "msg_active")
      user.update!(clinic_until: 1.minute.ago)
      post checkout_path, params: { plan: "clinic" }
      assert_redirected_to clinic_path
    end
    assert_not_requested :post, "#{API}/checkouts"
  end

  test "the page after paying waits for the webhook, then shows the credits" do
    user = make_user(credits: 0)
    sign_in_as(user)
    assert_equal 2, Credits.balance(user), "the free credits"

    get billing_success_path(plan: "look_pack")
    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "[role=status]", "Your credits arrive in a few seconds."
    assert_select "turbo-frame#billing-status[data-controller=poll]"

    body = dodo_body("payment_succeeded_pack", checkout: checkout_for(user))
    post dodo_webhook_path, params: body, headers: dodo_headers(body, id: "msg_pack").merge(JSON_HEADERS)

    get billing_success_path(plan: "look_pack")
    assert_select "[role=status]", "16 credits added. You have 18 credits."
    assert_select "turbo-frame#billing-status[data-controller]", count: 0
  end

  test "the provider's additions to the return address, the buyer's email among them, are dropped and never logged" do
    sign_in_as(make_user)

    log = capture_log { get billing_success_path(plan: "look_pack", status: "succeeded", email: "rosa@example.com", payment_id: "pay_1") }

    assert_redirected_to billing_success_path(plan: "look_pack", status: "succeeded")
    assert_not_includes log, "rosa@example.com"
  end

  test "a payment that didn't go through says so" do
    sign_in_as(make_user)

    get billing_success_path(plan: "look_pack", status: "failed")

    assert_select "h1", "The payment didn't go through"
  end

  test "manage opens only the portal of the account's own customer, and the link never reaches the log" do
    post billing_portal_path
    assert_redirected_to sign_in_path(origin: account_path)

    user = make_user
    sign_in_as(user)
    # A payment from someone else's customer, tied to this account by a forged reference, changes nothing here.
    BillingEvent.create!(provider: "dodo", event_id: "msg_x", event_type: "payment.succeeded", user:, customer_id: "cus_victim")
    post billing_portal_path
    assert_redirected_to account_path

    user.update!(billing_customer_id: "cus_own")
    stub_request(:post, "#{API}/customers/cus_own/customer-portal/session")
      .with(query: hash_including("return_url" => "http://www.example.com/account"))
      .to_return(status: 200, headers: JSON_HEADERS, body: { link: "https://test.customer.dodopayments.com/session/secret-link" }.to_json)
    log = capture_log { post billing_portal_path }

    assert_redirected_to "https://test.customer.dodopayments.com/session/secret-link"
    assert_not_includes log, "secret-link"
    assert_includes log, "Redirected to [FILTERED]"
  end

  test "the account lists purchases and the clinic plan with Manage" do
    user = make_user(credits: 0)
    sign_in_as(user)
    receive_dodo(dodo_body("payment_succeeded_pack", checkout: checkout_for(user)), id: "msg_pack")
    deliver_clinic(user)

    get account_path

    assert_select ".purchases li", 2
    assert_select ".purchases__what", "Look Pack: 16 credits"
    assert_select ".purchases__what", "Clinic plan, one month: 40 credits"
    assert_select "#clinic-plan-title ~ p", /Your Clinic plan is on\. It renews on/
    assert_select "form[action='#{billing_portal_path}'] button", "ManageWorking on it"
    assert_select "a[href='#{clinic_path}']"
    assert_empty CopyRules.problems(response.body)
  end

  test "a cancellation booked for the period end shows on the account" do
    user = make_user(credits: 0)
    sign_in_as(user)
    checkout = deliver_clinic(user)
    receive_dodo(dodo_body("subscription_active", checkout:, cancel_at_next_billing_date: true,
      next_billing_date: 1.month.from_now.utc.iso8601).sub('"subscription.active"', '"subscription.updated"'), id: "msg_updated")

    get account_path
    assert_select "#clinic-plan-title ~ p", /It won't renew\./
    get delete_account_path
    assert_not_includes response.body, "Your Clinic plan stops now too"
  end

  test "deleting the account stops every renewing Clinic subscription first" do
    user = make_user
    checkout = deliver_clinic(user)
    receive_dodo(dodo_body("subscription_active", checkout:, subscription_id: "sub_test_clinic_0002",
      next_billing_date: 1.month.from_now.utc.iso8601), id: "msg_second")
    sign_in_as(user)
    get delete_account_path
    assert_includes response.body, "Your Clinic plan stops now too, and won't be charged again."

    first = stub_request(:patch, "#{API}/subscriptions/sub_test_clinic_0001").with(body: hash_including("status" => "cancelled"))
      .to_return(status: 200, headers: JSON_HEADERS, body: "{}")
    # The second had been cancelled at Dodo already: that counts as stopped.
    stub_request(:patch, "#{API}/subscriptions/sub_test_clinic_0002").to_return(status: 409, body: "{}")
    stub_request(:get, "#{API}/subscriptions/sub_test_clinic_0002").to_return(status: 200, headers: JSON_HEADERS,
      body: JSON.parse(file_fixture("dodo/subscription_cancelled.json").read)["data"].to_json)
    delete account_path

    assert_requested first
    assert_redirected_to root_path
    assert_not User.exists?(user.id)
  end

  test "if the Clinic plan can't be stopped, nothing is deleted" do
    user = make_user
    deliver_clinic(user)
    sign_in_as(user)
    stub_request(:patch, "#{API}/subscriptions/sub_test_clinic_0001").to_return(status: 500, body: "{}")

    delete account_path

    assert_redirected_to account_path
    assert User.exists?(user.id)
  end

  test "deleting an account without a Clinic plan calls no one" do
    user = make_user
    sign_in_as(user)

    delete account_path

    assert_redirected_to root_path
    assert_not_requested :any, /dodopayments/
  end

  test "the client list needs sign in and the Clinic plan" do
    get clinic_path
    assert_redirected_to sign_in_path(origin: clinic_path)

    user = make_user
    sign_in_as(user)
    get clinic_path
    assert_redirected_to pricing_path(anchor: "clinic")

    post clinic_kits_path, params: { label: "Mrs Patel" }
    assert_redirected_to pricing_path(anchor: "clinic")
    assert_empty user.kits
  end

  test "a clinic sees only its own client kits, by label" do
    clinic = make_user
    clinic.update!(clinic_until: 1.month.from_now)
    mine = make_kit(path: :helper)
    mine.update!(user: clinic, label: "Mrs Patel")
    theirs = make_kit(path: :helper)
    theirs.update!(user: make_user, label: "Mr Jones")
    sign_in_as(clinic)

    get clinic_path

    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select ".clients h3", "Mrs Patel"
    assert_select ".clients", text: /Mr Jones/, count: 0
    assert_select "a[href='#{kit_path(mine)}']"
    assert_select "a[href='#{kit_shares_path(mine)}']"
    assert_select "a[href='#{kit_path(theirs)}']", count: 0
    assert_empty CopyRules.problems(response.body)
  end

  test "new client kit makes a labelled kit in the account, once per tap" do
    clinic = make_user
    clinic.update!(clinic_until: 1.month.from_now)
    sign_in_as(clinic)

    post clinic_kits_path, params: { label: "  Mrs   Patel " }
    kit = clinic.kits.sole
    assert_redirected_to kit_consent_path(kit)
    assert_equal [ "Mrs Patel", "helper" ], [ kit.label, kit.path ]

    post clinic_kits_path, params: { label: "Mrs Patel" }
    assert_equal 1, clinic.kits.count

    post clinic_kits_path, params: { label: " " }
    assert_redirected_to clinic_path
    post clinic_kits_path, params: { label: "x" * 41 }
    assert_redirected_to clinic_path
    assert_equal 1, clinic.kits.count
  end

  test "a print link shows once the client has a routine" do
    clinic = make_user
    clinic.update!(clinic_until: 1.month.from_now)
    kit = make_kit(path: :helper)
    kit.update!(user: clinic, label: "Mrs Patel")
    sign_in_as(clinic)

    get clinic_path
    assert_select "a[href='#{print_kit_routine_path(kit)}']", count: 0

    post kit_routine_path(kit), params: { look_key: "red_lip" }
    get clinic_path
    assert_select "a[href='#{print_kit_routine_path(kit)}']"
  end

  private
    def deliver_clinic(user)
      checkout = checkout_for(user, :clinic)
      receive_dodo(dodo_body("subscription_active", checkout:, next_billing_date: 1.month.from_now.utc.iso8601), id: "msg_clinic_#{user.id}")
      checkout
    end

    def customer_json(id)
      { customer_id: id, business_id: "bus_1", created_at: "2026-10-31T00:00:00Z", email: "rosa@example.com", name: "Rosa" }
    end

    def capture_log
      io = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io))
      ActionController::Base.logger = Rails.logger
      yield
      io.string
    ensure
      Rails.logger = original
      ActionController::Base.logger = original
    end
end
