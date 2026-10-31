require "test_helper"
require "support/dodo_webhooks"

class Billing::DodoTest < ActiveSupport::TestCase
  include DodoWebhooks

  User = Struct.new(:id, :email, :name)

  setup do
    @dodo = dodo_provider
    @user = User.new(42, "rosa@example.com", "Rosa Test")
  end

  test "parses a pack payment" do
    event = @dodo.parse_webhook(dodo_request(dodo_body("payment_succeeded_pack", user: @user), id: "msg_1"))

    assert_equal "msg_1", event.id
    assert_equal :pack_paid, event.type
    assert_equal "look_pack", event.plan.key
    assert_equal "42", event.user_id
    assert_equal "pay_test_pack_0001", event.payment_id
    assert_equal "cus_test_0001", event.customer_id
    assert_equal 799, event.amount_cents
  end

  test "a subscription's own payment is not a pack" do
    event = @dodo.parse_webhook(dodo_request(dodo_body("payment_succeeded_subscription", user: @user), id: "msg_2"))

    assert_nil event.type
  end

  test "parses each subscription event with its period end" do
    { "subscription_active" => :subscription_active, "subscription_renewed" => :subscription_renewed,
      "subscription_cancelled" => :subscription_cancelled, "subscription_expired" => :subscription_expired }.each do |name, type|
      event = @dodo.parse_webhook(dodo_request(dodo_body(name, user: @user), id: "msg_#{name}"))

      assert_equal type, event.type, name
      assert_equal "clinic", event.plan.key, name
      assert_equal "sub_test_clinic_0001", event.subscription_id, name
      assert_equal "42", event.user_id, name
      assert_kind_of Time, event.period_end, name
    end
  end

  test "parses a refund" do
    event = @dodo.parse_webhook(dodo_request(dodo_body("refund_succeeded"), id: "msg_3"))

    assert_equal :refund, event.type
    assert_equal "pay_test_pack_0001", event.payment_id
    assert_equal 799, event.amount_cents
  end

  test "the plan comes from the product, not from metadata" do
    body = dodo_body("payment_succeeded_pack", user: @user, product_cart: [ { product_id: "pdt_someone_else", quantity: 1 } ])
    event = @dodo.parse_webhook(dodo_request(body, id: "msg_4"))

    assert_equal :pack_paid, event.type
    assert_nil event.plan
  end

  test "keeps no names, emails or card details" do
    event = @dodo.parse_webhook(dodo_request(dodo_body("payment_succeeded_pack", user: @user), id: "msg_5"))
    stored = event.payload.to_json

    [ "buyer@example.com", "Test Buyer", "4242", "Test Street", "VISA" ].each { |detail| assert_not_includes stored, detail }
    assert_equal "cus_test_0001", event.payload.dig("data", "customer", "customer_id")
    assert_equal "42", event.payload.dig("data", "metadata", "user_id")
  end

  test "an event we don't act on has no type" do
    body = dodo_body("subscription_active").sub('"subscription.active"', '"dispute.opened"')

    assert_nil @dodo.parse_webhook(dodo_request(body, id: "msg_6")).type
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

  test "checkout sends the product, our user id and the return addresses" do
    stub = stub_request(:post, "https://test.dodopayments.com/checkouts").with { |request|
      body = JSON.parse(request.body)
      body["product_cart"] == [ { "product_id" => "pdt_test_look_pack", "quantity" => 1 } ] &&
        body["metadata"] == { "user_id" => "42", "plan" => "look_pack" } &&
        body["customer"]["email"] == "rosa@example.com" &&
        body["return_url"] == "https://blendolo.dijmo.com/billing/success?plan=look_pack" &&
        body["cancel_url"] == "https://blendolo.dijmo.com/pricing"
    }.to_return(status: 200, headers: { "Content-Type" => "application/json" },
      body: { session_id: "cks_1", checkout_url: "https://test.checkout.dodopayments.com/session/cks_1" }.to_json)

    url = @dodo.checkout_url(user: @user, plan: Billing::Plan.fetch(:look_pack),
      success_url: "https://blendolo.dijmo.com/billing/success?plan=look_pack", cancel_url: "https://blendolo.dijmo.com/pricing")

    assert_equal "https://test.checkout.dodopayments.com/session/cks_1", url
    assert_requested stub
  end

  test "checkout without a product id or key says what is missing" do
    plan = Billing::Plan.fetch(:clinic)

    assert_raises(Billing::NotConfigured) do
      dodo_provider(product_ids: {}).checkout_url(user: @user, plan:, success_url: "https://x.test/s", cancel_url: "https://x.test/c")
    end
    assert_raises(Billing::NotConfigured) do
      dodo_provider(api_key: nil).checkout_url(user: @user, plan:, success_url: "https://x.test/s", cancel_url: "https://x.test/c")
    end
  end

  test "a failing API is Unavailable, with no response body in the message" do
    stub_request(:post, "https://test.dodopayments.com/checkouts").to_return(status: 500, body: { secret: "x" }.to_json)

    error = assert_raises(Billing::Unavailable) do
      @dodo.checkout_url(user: @user, plan: Billing::Plan.fetch(:look_pack), success_url: "https://x.test/s", cancel_url: "https://x.test/c")
    end
    assert_not_includes error.message, "secret"
  end

  test "test mode unless the environment says live" do
    assert dodo_provider.test_mode?
    assert dodo_provider(environment: "nonsense").test_mode?
    assert_not dodo_provider(environment: "live_mode").test_mode?
  end
end
