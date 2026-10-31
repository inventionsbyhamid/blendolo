module Billing
  # One verified provider webhook in our words, made by the adapter's parse_webhook. BillingEvent reads only this.
  #   id                    the provider's event id (for Dodo, the signed webhook-id header): stored once
  #   type                  one of TYPES, or nil for an event we don't act on
  #   name                  the provider's own event name ("subscription.renewed"), for the log
  #   reference             the token of our Checkout, from the metadata our checkout sent. Only a hint: an account is
  #                         paid only when this resolves AND the paying customer is that account's own customer
  #   plan, quantity        the Billing::Plan of the product paid for (nil for a product that isn't ours), and how many
  #   customer_id, subscription_id, payment_id   the provider's ids
  #   money_back_id         a refund's or a dispute's own id
  #   subscription_status   the subscription's state at the provider ("active", "past_due", "cancelled", ...)
  #   cancel_at_period_end  true when it won't renew; nil when the event doesn't say
  #   period_end            when the subscription's paid period ends
  #   amount_cents, net_cents, currency   what was paid or taken back; net_cents before tax
  #   occurred_at           when the provider says it happened
  #   payload               what to keep in the log: ids, product, status, amounts and dates, never names, emails or cards
  class Event < Data.define(:id, :type, :name, :reference, :plan, :quantity, :customer_id, :subscription_id, :payment_id,
    :money_back_id, :subscription_status, :cancel_at_period_end, :period_end, :amount_cents, :net_cents, :currency,
    :occurred_at, :payload)
    TYPES = %i[pack_paid subscription_active subscription_renewed subscription_updated subscription_past_due
      subscription_cancelled subscription_expired refund dispute].freeze
    # Events that start or renew a paid period.
    PAID_PERIODS = %i[subscription_active subscription_renewed].freeze

    def initialize(id:, name:, type: nil, reference: nil, plan: nil, quantity: 1, customer_id: nil, subscription_id: nil,
      payment_id: nil, money_back_id: nil, subscription_status: nil, cancel_at_period_end: nil, period_end: nil,
      amount_cents: nil, net_cents: nil, currency: nil, occurred_at: nil, payload: {})
      raise ArgumentError, "unknown billing event type #{type.inspect}" unless type.nil? || TYPES.include?(type)

      super
    end

    def subscription? = type.to_s.start_with?("subscription_")
  end
end
