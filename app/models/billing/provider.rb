module Billing
  # The interface every payment provider adapter keeps. Nothing outside the adapter names a vendor.
  #
  #   name                       a short id ("dodo"), stored on BillingEvent
  #   test_mode?                 whether payments take test cards
  #   checkout_url(user:, plan:, success_url:, cancel_url:) -> String
  #                              a hosted checkout for one plan, carrying our user id. Raises NotConfigured, Unavailable.
  #   portal_url(user:, return_url:) -> String
  #                              the provider's customer portal (receipts, card, cancel). Raises NoCustomer, Unavailable.
  #   cancel_subscription(subscription_id)
  #                              stops a subscription now, so it is never charged again. Raises Unavailable.
  #   parse_webhook(request) -> Billing::Event
  #                              checks the signature on the raw body first. Raises InvalidSignature, NotConfigured.
  #   fee_cents(plan, worst:)    what the provider keeps from one payment for the plan (Billing::Margin)
  class Provider
    def name = raise(NotImplementedError)
    def test_mode? = raise(NotImplementedError)
    def checkout_url(user:, plan:, success_url:, cancel_url:) = raise(NotImplementedError)
    def portal_url(user:, return_url:) = raise(NotImplementedError)
    def cancel_subscription(subscription_id) = raise(NotImplementedError)
    def parse_webhook(request) = raise(NotImplementedError)
    def fee_cents(plan, worst: true) = raise(NotImplementedError)
  end
end
