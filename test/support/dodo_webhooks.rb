require "base64"

# Dodo webhooks for tests: recorded-shape payloads (test/fixtures/files/dodo, made-up ids and people) signed the
# Standard Webhooks way with a test secret, and an adapter that knows the test product ids. Nothing here reaches the
# network.
module DodoWebhooks
  SECRET = "whsec_#{Base64.strict_encode64('blendolo test webhook secret 32b')}".freeze
  PRODUCTS = { "look_pack" => "pdt_test_look_pack", "clinic" => "pdt_test_clinic" }.freeze
  API = "https://test.dodopayments.com".freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  def dodo_provider(**options)
    Billing::Dodo.new(api_key: "dodo_test_key", webhook_secret: SECRET, environment: "test_mode", product_ids: PRODUCTS,
      **options)
  end

  # A checkout our server started for the account, with the account's own customer at Dodo (as Billing.start_checkout!
  # leaves them).
  def checkout_for(user, plan = :look_pack)
    user.update!(billing_customer_id: "cus_test_#{user.id}") if user.billing_customer_id.blank?
    Checkout.create!(user:, provider: "dodo", plan: plan.to_s, url: "https://test.checkout.dodopayments.com/session/cks_#{user.id}")
  end

  # A fixture's JSON body, with data fields changed. checkout: carries its reference and its account's customer, as
  # Dodo does for a session our server made.
  def dodo_body(name, checkout: nil, **data)
    payload = JSON.parse(file_fixture("dodo/#{name}.json").read)
    if checkout
      payload["data"]["metadata"] = payload["data"].fetch("metadata", {}).merge("ref" => checkout.token)
      payload["data"]["customer"] = payload["data"].fetch("customer", {}).merge("customer_id" => checkout.user.billing_customer_id)
    end
    payload["data"].merge!(data.transform_keys(&:to_s))
    JSON.generate(payload)
  end

  def dodo_headers(body, id:, secret: SECRET, at: Time.current)
    timestamp = at.to_i.to_s
    signature = StandardWebhooks::Webhook.new(secret).sign(id, timestamp, body)
    { "webhook-id" => id, "webhook-timestamp" => timestamp, "webhook-signature" => signature }
  end

  # Something with what Billing::Dodo#parse_webhook reads from a request.
  WebhookRequest = Struct.new(:raw_post, :headers)

  def dodo_request(body, **options)
    WebhookRequest.new(body, dodo_headers(body, **options))
  end

  # Stores and applies a body as the webhook endpoint would, without the request.
  def receive_dodo(body, id:)
    BillingEvent.receive!(dodo_provider.parse(body, id:), provider: "dodo")
  end
end
