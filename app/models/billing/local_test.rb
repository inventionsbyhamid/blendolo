module Billing
  # The payment provider for local development without a Dodo key (config.x.local_billing; Billing.provider picks it
  # only then, so never in production). It keeps the Billing::Provider interface: the account gets its own local
  # customer id, checkout goes to a local page (Local::BillingController) carrying the Checkout's reference, and
  # "Pay" makes the event a verified webhook would bring, with that reference and the account's customer, and hands it
  # to BillingEvent.receive!, the webhook's own code. So the local flow takes the real path: the reference must resolve
  # and the customer must match, or nothing is added. Nothing is charged, no card is asked for, nothing leaves the
  # machine.
  class LocalTest < Provider
    NAME = "local_test".freeze

    def name = NAME

    # No cards at all: the checkout page itself says it is a local test.
    def test_mode? = false

    def create_customer(email:, name:)
      local_id("cus")
    end

    def checkout_url(customer_id:, plan:, reference:, success_url:, cancel_url:)
      routes.local_checkout_path(ref: reference, success_url:, cancel_url:)
    end

    def portal_url(customer_id:, return_url:)
      routes.local_portal_path(return_url:)
    end

    # What a paid checkout's webhook would say: a pack paid for, or a Clinic plan's first month, from the Checkout's
    # reference and its account's own customer.
    def payment_event(checkout)
      plan = Plan.fetch(checkout.plan)
      monthly = plan.subscription?
      Event.new(id: local_id("evt"), name: monthly ? "subscription.active" : "payment.succeeded",
        type: monthly ? :subscription_active : :pack_paid, reference: checkout.token, plan:,
        customer_id: checkout.user&.billing_customer_id, subscription_id: (local_id("sub") if monthly),
        payment_id: local_id("pay"), subscription_status: ("active" if monthly), cancel_at_period_end: (false if monthly),
        period_end: (1.month.from_now if monthly), amount_cents: plan.price_cents, net_cents: plan.price_cents,
        currency: "USD", occurred_at: Time.current, payload: { "local_test" => true, "plan" => plan.key })
    end

    # Stops a subscription the way the provider's "cancelled" webhook does: it won't renew, and the plan stays on until
    # its paid month ends.
    def cancel_subscription(subscription_id)
      subscription = BillingSubscription.find_by(provider: NAME, subscription_id:)
      return :already_ended unless subscription&.renewing?

      BillingEvent.receive!(Event.new(id: local_id("evt"), name: "subscription.cancelled", type: :subscription_cancelled,
        plan: subscription.plan_record, customer_id: subscription.user&.billing_customer_id, subscription_id:,
        subscription_status: "cancelled", cancel_at_period_end: true, period_end: subscription.period_end,
        occurred_at: Time.current, payload: { "local_test" => true }), provider: NAME)
      :cancelled
    end

    # Nothing outside this machine can pay, so no webhook is ever believed.
    def parse_webhook(request)
      raise InvalidSignature, "the local test provider takes no webhooks"
    end

    # Nothing is charged.
    def fee_cents(plan, worst: true) = 0

    private
      def routes = Rails.application.routes.url_helpers
      def local_id(kind) = "local_#{kind}_#{SecureRandom.hex(8)}"
  end
end
