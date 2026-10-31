module Billing
  # The payment provider for local development without a Dodo key (config.x.local_billing; Billing.provider picks it
  # only then, so never in production). Checkout is a local page (Local::BillingController) whose "Pay" button makes
  # the event a verified webhook would bring and hands it to BillingEvent.receive!, the webhook's own code, so the
  # credits and the Clinic plan arrive the normal way. Nothing is charged, no card is asked for, and nothing leaves
  # the machine.
  class LocalTest < Provider
    NAME = "local_test".freeze

    def name = NAME

    # No cards at all: the checkout page itself says it is a local test.
    def test_mode? = false

    def checkout_url(user:, plan:, success_url:, cancel_url:)
      routes.local_checkout_path(plan: plan.key, success_url:, cancel_url:)
    end

    def portal_url(user:, return_url:)
      raise NoCustomer, "No local test payments yet" unless BillingEvent.customer_id_for(user, provider: NAME)

      routes.local_portal_path(return_url:)
    end

    # What a paid checkout's webhook would say: a pack paid for, or a Clinic plan's first month.
    def payment_event(user:, plan:)
      monthly = plan.subscription?
      Event.new(id: local_id("evt"), name: monthly ? "subscription.active" : "payment.succeeded",
        type: monthly ? :subscription_active : :pack_paid, user_id: user.id.to_s, plan:,
        customer_id: "local_cus_#{user.id}", subscription_id: (local_id("sub") if monthly), payment_id: local_id("pay"),
        period_end: (1.month.from_now if monthly), amount_cents: plan.price_cents, currency: "USD",
        payload: { "local_test" => true, "plan" => plan.key })
    end

    # Stops the plan the way the provider's "cancelled" webhook does: it stays on until its paid month ends.
    def cancel_subscription(subscription_id)
      paid = BillingEvent.where(provider: NAME, subscription_id:, kind: BillingEvent::CLINIC_STARTS).order(:id).last
      return unless paid

      BillingEvent.receive!(Event.new(id: local_id("evt"), name: "subscription.cancelled", type: :subscription_cancelled,
        plan: paid.plan_record, customer_id: paid.customer_id, subscription_id:, period_end: paid.period_end,
        payload: { "local_test" => true }), provider: NAME)
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
