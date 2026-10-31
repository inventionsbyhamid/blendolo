require "test_helper"
require "support/dodo_webhooks"

class Billing::DodoTest < ActiveSupport::TestCase
  include DodoWebhooks

  setup { @dodo = dodo_provider }

  test "parses a pack payment" do
    event = @dodo.parse_webhook(dodo_request(dodo_body("payment_succeeded_pack"), id: "msg_1"))

    assert_equal "msg_1", event.id
    assert_equal :pack_paid, event.type
    assert_equal "look_pack", event.plan.key
    assert_equal "ref_not_ours", event.reference
    assert_equal [ "pay_test_pack_0001", "cus_test_0001", 799, 799, 1 ],
      [ event.payment_id, event.customer_id, event.amount_cents, event.net_cents, event.quantity ]
    assert_equal Time.iso8601("2026-11-01T10:00:04Z"), event.occurred_at
  end

  test "a payment's quantity comes from the cart" do
    body = dodo_body("payment_succeeded_pack", product_cart: [ { product_id: "pdt_test_look_pack", quantity: 3 } ])

    assert_equal 3, @dodo.parse_webhook(dodo_request(body, id: "msg_q")).quantity
  end

  test "a subscription's own payment is not a pack" do
    event = @dodo.parse_webhook(dodo_request(dodo_body("payment_succeeded_subscription"), id: "msg_2"))

    assert_nil event.type
    assert_equal [ "pay_test_clinic_0001", "sub_test_clinic_0001" ], [ event.payment_id, event.subscription_id ]
  end

  test "parses each subscription event with its state and period end" do
    { "subscription_active" => [ :subscription_active, "active", false ],
      "subscription_renewed" => [ :subscription_renewed, "active", false ],
      "subscription_cancelled" => [ :subscription_cancelled, "cancelled", true ],
      "subscription_expired" => [ :subscription_expired, "expired", true ] }.each do |name, (type, status, cancelling)|
      event = @dodo.parse_webhook(dodo_request(dodo_body(name), id: "msg_#{name}"))

      assert_equal [ type, status, cancelling ], [ event.type, event.subscription_status, event.cancel_at_period_end ], name
      assert_equal [ "clinic", "sub_test_clinic_0001", 1900 ], [ event.plan.key, event.subscription_id, event.net_cents ], name
      assert_kind_of Time, event.period_end, name
    end
  end

  test "maps updates, retries and money taken back" do
    { "subscription.updated" => :subscription_updated, "subscription.past_due" => :subscription_past_due,
      "subscription.on_hold" => :subscription_past_due, "dispute.opened" => :dispute, "dispute.lost" => :dispute,
      "dispute.won" => nil, "subscription.failed" => nil }.each do |name, type|
      body = dodo_body("subscription_active").sub('"subscription.active"', %("#{name}"))

      parsed = @dodo.parse_webhook(dodo_request(body, id: "msg_#{name}")).type
      type ? assert_equal(type, parsed, name) : assert_nil(parsed, name)
    end
  end

  test "parses a refund and a dispute" do
    refund = @dodo.parse_webhook(dodo_request(dodo_body("refund_succeeded"), id: "msg_3"))
    dispute = @dodo.parse_webhook(dodo_request(dodo_body("dispute_opened"), id: "msg_4"))

    assert_equal [ :refund, "pay_test_pack_0001", "ref_test_0001", 799 ],
      [ refund.type, refund.payment_id, refund.money_back_id, refund.amount_cents ]
    assert_equal [ :dispute, "pay_test_pack_0001", "dsp_test_0001" ], [ dispute.type, dispute.payment_id, dispute.money_back_id ]
  end

  test "the plan comes from the product, not from metadata" do
    body = dodo_body("payment_succeeded_pack", product_cart: [ { product_id: "pdt_someone_else", quantity: 1 } ])
    event = @dodo.parse_webhook(dodo_request(body, id: "msg_5"))

    assert_equal :pack_paid, event.type
    assert_nil event.plan
  end

  test "keeps no names, emails or card details" do
    event = @dodo.parse_webhook(dodo_request(dodo_body("payment_succeeded_pack"), id: "msg_6"))
    stored = event.payload.to_json

    [ "buyer@example.com", "Test Buyer", "4242", "Test Street", "VISA" ].each { |detail| assert_not_includes stored, detail }
    assert_equal "cus_test_0001", event.payload.dig("data", "customer", "customer_id")
    assert_equal "ref_not_ours", event.payload.dig("data", "metadata", "ref")
  end

  test "rejects a body signed with another secret" do
    body = dodo_body("payment_succeeded_pack")
    other = "whsec_#{Base64.strict_encode64('someone else entirely, 32 bytes!')}"

    assert_raises(Billing::InvalidSignature) { @dodo.parse_webhook(dodo_request(body, id: "msg_7", secret: other)) }
  end

  test "rejects a changed body" do
    request = dodo_request(dodo_body("payment_succeeded_pack"), id: "msg_8")
    request.raw_post = request.raw_post.sub("799", "1")

    assert_raises(Billing::InvalidSignature) { @dodo.parse_webhook(request) }
  end

  test "rejects an old delivery replayed" do
    request = dodo_request(dodo_body("payment_succeeded_pack"), id: "msg_9", at: 10.minutes.ago)

    assert_raises(Billing::InvalidSignature) { @dodo.parse_webhook(request) }
  end

  test "rejects missing and malformed signature headers" do
    body = dodo_body("payment_succeeded_pack")
    headers = dodo_headers(body, id: "msg_10")

    [ headers.except("webhook-signature"), headers.merge("webhook-signature" => "v1,"),
      headers.merge("webhook-signature" => "nonsense"), headers.merge("webhook-timestamp" => "soon") ].each do |bad|
      assert_raises(Billing::InvalidSignature) { @dodo.parse_webhook(WebhookRequest.new(body, bad)) }
    end
  end

  test "without a webhook secret nothing is trusted" do
    request = dodo_request(dodo_body("payment_succeeded_pack"), id: "msg_11")

    assert_raises(Billing::NotConfigured) { dodo_provider(webhook_secret: nil).parse_webhook(request) }
  end

  test "makes a customer with the account's email" do
    stub = stub_request(:post, "#{API}/customers").with(body: hash_including("email" => "rosa@example.com", "name" => "Rosa"))
      .to_return(status: 200, headers: JSON_HEADERS, body: customer_json("cus_new").to_json)

    assert_equal "cus_new", @dodo.create_customer(email: "rosa@example.com", name: "Rosa")
    assert_requested stub
  end

  test "checkout is for the account's own customer, with the email locked, one of the plan and our reference" do
    stub = stub_request(:post, "#{API}/checkouts").with { |request|
      body = JSON.parse(request.body)
      body["product_cart"] == [ { "product_id" => "pdt_test_look_pack", "quantity" => 1 } ] &&
        body["customer"] == { "customer_id" => "cus_42" } &&
        body["feature_flags"] == { "allow_customer_editing_email" => false, "allow_discount_code" => false } &&
        body["metadata"] == { "ref" => "tok_1", "plan" => "look_pack" } &&
        body["return_url"] == "https://blendolo.dijmo.com/billing/success?plan=look_pack" &&
        body["cancel_url"] == "https://blendolo.dijmo.com/pricing"
    }.to_return(status: 200, headers: JSON_HEADERS,
      body: { session_id: "cks_1", checkout_url: "https://test.checkout.dodopayments.com/session/cks_1" }.to_json)

    url = @dodo.checkout_url(customer_id: "cus_42", plan: Billing::Plan.fetch(:look_pack), reference: "tok_1",
      success_url: "https://blendolo.dijmo.com/billing/success?plan=look_pack", cancel_url: "https://blendolo.dijmo.com/pricing")

    assert_equal "https://test.checkout.dodopayments.com/session/cks_1", url
    assert_requested stub
  end

  test "checkout without a product id or key says what is missing" do
    plan = Billing::Plan.fetch(:clinic)
    args = { customer_id: "cus_42", plan:, reference: "tok", success_url: "https://x.test/s", cancel_url: "https://x.test/c" }

    assert_raises(Billing::NotConfigured) { dodo_provider(product_ids: {}).checkout_url(**args) }
    assert_raises(Billing::NotConfigured) { dodo_provider(api_key: nil).checkout_url(**args) }
  end

  test "a failing API is Unavailable, with no response body in the message" do
    stub_request(:post, "#{API}/checkouts").to_return(status: 500, body: { secret: "x" }.to_json)

    error = assert_raises(Billing::Unavailable) do
      @dodo.checkout_url(customer_id: "cus_42", plan: Billing::Plan.fetch(:look_pack), reference: "tok",
        success_url: "https://x.test/s", cancel_url: "https://x.test/c")
    end
    assert_not_includes error.message, "secret"
  end

  test "cancelling: done, already ended, or a real failure" do
    stub_request(:patch, "#{API}/subscriptions/sub_ok").to_return(status: 200, headers: JSON_HEADERS, body: "{}")
    assert_equal :cancelled, @dodo.cancel_subscription("sub_ok")

    stub_request(:patch, "#{API}/subscriptions/sub_gone").to_return(status: 409, body: "{}")
    stub_request(:get, "#{API}/subscriptions/sub_gone").to_return(status: 200, headers: JSON_HEADERS, body: subscription_json("cancelled").to_json)
    assert_equal :already_ended, @dodo.cancel_subscription("sub_gone")

    stub_request(:patch, "#{API}/subscriptions/sub_stuck").to_return(status: 422, body: "{}")
    stub_request(:get, "#{API}/subscriptions/sub_stuck").to_return(status: 200, headers: JSON_HEADERS, body: subscription_json("active").to_json)
    assert_raises(Billing::Unavailable) { @dodo.cancel_subscription("sub_stuck") }

    stub_request(:patch, "#{API}/subscriptions/sub_down").to_return(status: 503, body: "{}")
    assert_raises(Billing::Unavailable) { @dodo.cancel_subscription("sub_down") }
  end

  test "test mode unless the environment says live" do
    assert dodo_provider.test_mode?
    assert dodo_provider(environment: "nonsense").test_mode?
    assert_not dodo_provider(environment: "live_mode").test_mode?
  end

  test "asks for every event it acts on" do
    assert_equal Billing::Dodo::SUBSCRIBED.sort, Billing::Dodo::EVENT_TYPES.keys.push("payment.succeeded").sort
  end

  private
    def customer_json(id)
      { customer_id: id, business_id: "bus_1", created_at: "2026-10-31T00:00:00Z", email: "rosa@example.com", name: "Rosa" }
    end

    def subscription_json(status)
      JSON.parse(file_fixture("dodo/subscription_active.json").read)["data"].merge("status" => status, "subscription_id" => "sub_x")
    end
end
