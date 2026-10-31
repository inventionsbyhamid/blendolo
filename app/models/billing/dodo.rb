module Billing
  # Dodo Payments, the merchant of record: the one place the app uses the dodopayments and standardwebhooks gems.
  #
  # Env: DODO_API_KEY (customers, checkout, the portal, cancelling), DODO_WEBHOOK_SECRET (webhooks),
  # DODO_PRODUCT_LOOK_PACK and DODO_PRODUCT_CLINIC (a product id per paid plan), DODO_ENVIRONMENT (test_mode unless it
  # says live_mode: the gem itself defaults to live, so the environment is always passed).
  class Dodo < Provider
    NAME = "dodo".freeze

    # Dodo's event names => ours. payment.succeeded is a pack only when it belongs to no subscription (a
    # subscription's own payments come with subscription events). A dispute counts once the money is taken back
    # (opened, accepted or lost: the first one counts). Anything else is stored and changes nothing.
    EVENT_TYPES = {
      "subscription.active" => :subscription_active,
      "subscription.renewed" => :subscription_renewed,
      "subscription.updated" => :subscription_updated,
      "subscription.past_due" => :subscription_past_due,
      "subscription.on_hold" => :subscription_past_due,
      "subscription.cancelled" => :subscription_cancelled,
      "subscription.expired" => :subscription_expired,
      "refund.succeeded" => :refund,
      "dispute.opened" => :dispute,
      "dispute.accepted" => :dispute,
      "dispute.lost" => :dispute
    }.freeze
    # The webhook events the endpoint asks for (script/billing/dodo_setup.rb).
    SUBSCRIBED = [ "payment.succeeded", *EVENT_TYPES.keys ].freeze

    SIGNATURE_HEADERS = %w[webhook-id webhook-timestamp webhook-signature].freeze
    # One entry of webhook-signature (there may be several, space separated): a version, a comma, then base64.
    SIGNATURE_ENTRY = %r{\Av\d+[a-z]?,[A-Za-z0-9+/]+={0,2}\z}

    # What a stored webhook keeps: ids, product, status, amounts and dates, and our own metadata. Never the customer's
    # name, email, phone, address or card.
    STORED_FIELDS = %w[payload_type payment_id subscription_id refund_id dispute_id product_id quantity status
      dispute_status currency total_amount tax amount recurring_pre_tax_amount is_partial previous_billing_date
      next_billing_date past_due_ends_at cancel_at_next_billing_date cancelled_at expires_at created_at].freeze
    STORED_METADATA = %w[ref plan].freeze
    # A subscription is over for good in these states.
    ENDED = %w[cancelled expired failed].freeze

    # Dodo's standard pricing (dodopayments.com/pricing, read 2026-10-31): 4% + 40 cents a payment by US card or
    # wallet, plus 1.5% for a card from outside the US, 0.5% on subscriptions, and 3% for PayPal or pay later. The
    # worst case adds every surcharge. Refunds ($1) and disputes ($30) are per case, not per payment.
    FEES = { rate: 0.04, fixed_cents: 40, international: 0.015, subscription: 0.005, paypal: 0.03 }.freeze

    # The buyer waits on checkout and the portal: fail fast instead of the gem's default minute.
    TIMEOUT = 15

    def initialize(api_key: ENV["DODO_API_KEY"], webhook_secret: ENV["DODO_WEBHOOK_SECRET"],
      environment: ENV["DODO_ENVIRONMENT"], product_ids: nil)
      @api_key = api_key.presence
      @webhook_secret = webhook_secret.presence
      @environment = environment.to_s.strip == "live_mode" ? :live_mode : :test_mode
      @product_ids = product_ids || Plan.all.to_h { |plan| [ plan.key, ENV["DODO_PRODUCT_#{plan.key.upcase}"].presence ] }
    end

    def name = NAME

    def test_mode?
      @environment == :test_mode
    end

    def create_customer(email:, name:)
      call_api("customer") { client.customers.create(email:, name:) }.customer_id
    end

    # Attached to the account's own customer, with the email locked and no discount box, for one of the plan; the
    # reference comes back on the webhooks.
    def checkout_url(customer_id:, plan:, reference:, success_url:, cancel_url:)
      product_id = @product_ids[plan.key] or raise NotConfigured, "DODO_PRODUCT_#{plan.key.upcase} is not set"

      session = call_api("checkout") do
        client.checkout_sessions.create(
          product_cart: [ { product_id:, quantity: 1 } ],
          customer: { customer_id: },
          feature_flags: { allow_customer_editing_email: false, allow_discount_code: false },
          metadata: { ref: reference, plan: plan.key },
          return_url: success_url,
          cancel_url: cancel_url,
          customization: { theme: :light }
        )
      end
      session.checkout_url.presence or raise Unavailable, "Dodo gave no checkout URL"
    end

    def portal_url(customer_id:, return_url:)
      call_api("customer portal") { client.customers.customer_portal.create(customer_id, return_url:) }.link
    end

    # A 4xx means Dodo won't change it: if it has ended anyway, that is what we wanted.
    def cancel_subscription(subscription_id)
      client.subscriptions.update(subscription_id, status: :cancelled)
      :cancelled
    rescue Dodopayments::Errors::APIStatusError => e
      raise Unavailable, "Dodo cancel failed (#{e.status})" unless e.status.to_i.between?(400, 499)

      status = call_api("subscription") { client.subscriptions.retrieve(subscription_id) }.status.to_s
      ENDED.include?(status) ? :already_ended : raise(Unavailable, "Dodo cancel refused (#{e.status}, still #{status})")
    rescue Dodopayments::Errors::Error => e
      raise Unavailable, "Dodo cancel failed (#{e.class.name.demodulize})"
    end

    def parse_webhook(request)
      body = request.raw_post.to_s
      parse(body, id: verify!(body, request.headers))
    end

    # The event in a verified body. Never raises, whatever the body's shape: an event we can't read has no type.
    def parse(body, id:)
      payload = object(JSON.parse(body))
      data = object(payload["data"])
      metadata = object(data["metadata"])
      name = text(payload["type"]).to_s
      cart = object(Array(data["product_cart"]).first)
      Event.new(
        id:, name:, type: type_for(name, data), reference: text(metadata["ref"]), plan: plan_for(data, cart),
        quantity: [ integer(data["quantity"] || cart["quantity"]) || 1, 1 ].max,
        customer_id: text(object(data["customer"])["customer_id"]), subscription_id: text(data["subscription_id"]),
        payment_id: text(data["payment_id"]), money_back_id: text(data["refund_id"]) || text(data["dispute_id"]),
        subscription_status: (text(data["status"]) if data["payload_type"] == "Subscription"),
        cancel_at_period_end: flag(data["cancel_at_next_billing_date"]), period_end: time(data["next_billing_date"]),
        amount_cents: integer(data["total_amount"]) || integer(data["amount"]),
        net_cents: net_cents(data), currency: text(data["currency"]), occurred_at: time(payload["timestamp"]),
        payload: stored(payload, data, metadata)
      )
    rescue JSON::ParserError
      Event.new(id:, name: "")
    end

    def fee_cents(plan, worst: true)
      rate = FEES[:rate]
      rate += FEES[:international] + FEES[:paypal] if worst
      rate += FEES[:subscription] if plan.subscription?
      (plan.price_cents * rate).round + FEES[:fixed_cents]
    end

    private
      def client
        raise NotConfigured, "DODO_API_KEY is not set" unless @api_key

        @client ||= Dodopayments::Client.new(bearer_token: @api_key, environment: @environment, timeout: TIMEOUT,
          max_retries: 1)
      end

      def call_api(what)
        yield
      rescue Dodopayments::Errors::Error => e
        raise Unavailable, "Dodo #{what} failed (#{e.class.name.demodulize}#{" #{e.status}" if e.respond_to?(:status) && e.status})"
      end

      # Standard Webhooks (standardwebhooks.com): an HMAC-SHA256 of "id.timestamp.body" under the secret, and a
      # timestamp within 5 minutes of now, so a captured webhook can't be replayed later. Returns the event id.
      def verify!(body, headers)
        raise NotConfigured, "DODO_WEBHOOK_SECRET is not set" unless @webhook_secret

        values = SIGNATURE_HEADERS.index_with { |header| headers[header].presence }
        raise InvalidSignature, "missing webhook headers" if values.values.any?(&:nil?)
        # The gem crashes on an entry with nothing after its comma, so the header's shape is checked first.
        raise InvalidSignature, "malformed webhook-signature" unless well_formed?(values["webhook-signature"])

        StandardWebhooks::Webhook.new(@webhook_secret).verify(body, values)
        values.fetch("webhook-id")
      rescue StandardWebhooks::StandardWebhooksError, JSON::ParserError, ArgumentError, TypeError, NoMethodError => e
        raise InvalidSignature, e.message
      end

      def well_formed?(header)
        entries = header.to_s.split(" ")
        entries.any? && entries.all? { |entry| SIGNATURE_ENTRY.match?(entry) }
      end

      def type_for(name, data)
        return EVENT_TYPES[name] unless name == "payment.succeeded"

        :pack_paid if text(data["subscription_id"]).nil? && Array(data["subscription_ids"]).empty?
      end

      # The plan comes from the product paid for, never from metadata: a product of the business that isn't ours
      # gives nil.
      def plan_for(data, cart)
        product_id = text(data["product_id"]) || text(cart["product_id"])
        key = @product_ids.key(product_id) if product_id
        Plan.find(key) if key
      end

      # Before tax: a payment's total less its tax, or a subscription's recurring amount.
      def net_cents(data)
        total = integer(data["total_amount"])
        return total - (integer(data["tax"]) || 0) if total

        integer(data["recurring_pre_tax_amount"])
      end

      def stored(payload, data, metadata)
        kept = data.slice(*STORED_FIELDS)
        kept["customer"] = object(data["customer"]).slice("customer_id") if data.key?("customer")
        kept["metadata"] = metadata.slice(*STORED_METADATA) if data.key?("metadata")
        kept["product_cart"] = Array(data["product_cart"]).map { |item| object(item).slice("product_id", "quantity") } if data.key?("product_cart")
        payload.slice("business_id", "type", "timestamp").merge("data" => kept)
      end

      # Readers that never raise, for a payload of any shape.
      def object(value) = value.is_a?(Hash) ? value : {}
      def text(value) = (value.to_s.presence if value.is_a?(String) || value.is_a?(Integer))
      def integer(value) = (value if value.is_a?(Integer))
      def flag(value) = (value if [ true, false ].include?(value))

      def time(value)
        Time.iso8601(value) if value.is_a?(String)
      rescue ArgumentError
        nil
      end
  end
end
