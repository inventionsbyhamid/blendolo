module Billing
  # One verified provider webhook in our words, made by the adapter's parse_webhook. BillingEvent reads only this.
  #   id               the provider's event id (for Dodo, the signed webhook-id header): stored once
  #   type             one of TYPES, or nil for an event we don't act on
  #   name             the provider's own event name ("subscription.renewed"), for the log
  #   user_id          our user id, from the metadata our checkout sent (nil when there is none)
  #   plan             the Billing::Plan paid for, from the provider's product id (nil for a product that isn't ours)
  #   customer_id, subscription_id, payment_id   the provider's ids
  #   period_end       when the subscription's paid period ends
  #   amount_cents, currency                     what was paid or refunded
  #   payload          what to keep in the log: ids, product, status, amounts and dates, never names, emails or cards
  class Event < Data.define(:id, :type, :name, :user_id, :plan, :customer_id, :subscription_id, :payment_id,
    :period_end, :amount_cents, :currency, :payload)
    TYPES = %i[pack_paid subscription_active subscription_renewed subscription_cancelled subscription_expired refund].freeze

    def initialize(id:, name:, type: nil, user_id: nil, plan: nil, customer_id: nil, subscription_id: nil,
      payment_id: nil, period_end: nil, amount_cents: nil, currency: nil, payload: {})
      raise ArgumentError, "unknown billing event type #{type.inspect}" unless type.nil? || TYPES.include?(type)

      super
    end
  end
end
