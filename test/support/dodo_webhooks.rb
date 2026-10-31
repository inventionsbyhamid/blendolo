require "base64"

# Dodo webhooks for tests: recorded-shape payloads (test/fixtures/files/dodo, made-up ids and people) signed the
# Standard Webhooks way with a test secret, and an adapter that knows the test product ids. Nothing here reaches the
# network.
module DodoWebhooks
  SECRET = "whsec_#{Base64.strict_encode64('blendolo test webhook secret 32b')}".freeze
  PRODUCTS = { "look_pack" => "pdt_test_look_pack", "clinic" => "pdt_test_clinic" }.freeze

  def dodo_provider(**options)
    Billing::Dodo.new(api_key: "dodo_test_key", webhook_secret: SECRET, environment: "test_mode", product_ids: PRODUCTS,
      **options)
  end

  # A fixture's JSON body, with data fields changed (user: sets metadata.user_id).
  def dodo_body(name, user: nil, **data)
    payload = JSON.parse(file_fixture("dodo/#{name}.json").read)
    payload["data"]["metadata"] = payload["data"].fetch("metadata", {}).merge("user_id" => user.id.to_s) if user
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
end
