module Billing
  # The interface every payment provider adapter keeps. Nothing outside the adapter names a vendor; Billing (the
  # module) does the account side: one customer per account, a Checkout reference per checkout.
  #
  #   name                       a short id ("dodo"), stored on BillingEvent, Checkout and BillingSubscription
  #   test_mode?                 whether payments take test cards
  #   create_customer(email:, name:) -> String
  #                              makes the account's own customer at the provider and returns its id. Raises
  #                              NotConfigured, Unavailable.
  #   checkout_url(customer_id:, plan:, reference:, success_url:, cancel_url:) -> String
  #                              a hosted checkout for one of the plan, for that customer only (the email can't be
  #                              changed there), carrying reference in its metadata. Raises NotConfigured, Unavailable.
  #   portal_url(customer_id:, return_url:) -> String
  #                              the provider's customer portal for that customer (receipts, card, cancel). Raises
  #                              Unavailable.
  #   cancel_subscription(subscription_id) -> :cancelled or :already_ended
  #                              stops a subscription now, so it is never charged again; one that had already ended
  #                              is fine. Raises Unavailable (network or provider trouble).
  #   parse_webhook(request) -> Billing::Event
  #                              checks the signature on the raw body first. Raises InvalidSignature, NotConfigured.
  #   fee_cents(plan, worst:)    what the provider keeps from one payment for the plan (Billing::Margin)
  class Provider
    def name = raise(NotImplementedError)
    def test_mode? = raise(NotImplementedError)
    def create_customer(email:, name:) = raise(NotImplementedError)
    def checkout_url(customer_id:, plan:, reference:, success_url:, cancel_url:) = raise(NotImplementedError)
    def portal_url(customer_id:, return_url:) = raise(NotImplementedError)
    def cancel_subscription(subscription_id) = raise(NotImplementedError)
    def parse_webhook(request) = raise(NotImplementedError)
    def fee_cents(plan, worst: true) = raise(NotImplementedError)
  end
end
