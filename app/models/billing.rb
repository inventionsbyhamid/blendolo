# Payments, behind one vendor-neutral interface (Billing::Provider). App code talks to Billing.provider, Billing::Plan
# and Billing::Event only; the vendor adapter (Billing::Dodo) is the one place that names a vendor, so another provider
# is one more adapter. Plans, prices and credits are ours (config/blendolo/plans.yml); the provider sells a product
# id per paid plan and tells us, by signed webhook, what was paid. Credits are granted only from a verified webhook,
# never from the page the buyer comes back to. In local development without a Dodo key, Billing::LocalTest stands in.
module Billing
  class Error < StandardError; end
  # A webhook whose signature or signature headers don't check out.
  class InvalidSignature < Error; end
  # A key, webhook secret or product id isn't set.
  class NotConfigured < Error; end
  # The provider's API failed: network, auth or an answer we can't use.
  class Unavailable < Error; end
  # There is nothing to manage yet: this account never paid.
  class NoCustomer < Error; end

  class << self
    attr_writer :provider

    def provider
      @provider ||= Rails.configuration.x.local_billing ? LocalTest.new : Dodo.new
    end

    # Whether payments take test cards (Dodo test mode). Pages say so.
    def test_mode?
      provider.test_mode?
    end

    # Stops the account's Clinic plan at the provider now, before the account is deleted, so it is never charged
    # again. Nothing to do when it won't renew anyway. Raises Unavailable when the provider can't be reached.
    def cancel_subscriptions!(user)
      renewing = BillingEvent.renewing_subscription_for(user) or return
      provider.cancel_subscription(renewing.subscription_id)
    end
  end
end
