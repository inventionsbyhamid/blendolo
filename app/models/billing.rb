# Payments, behind one vendor-neutral interface (Billing::Provider). App code talks to Billing.provider, Billing::Plan
# and Billing::Event only; the vendor adapter (Billing::Dodo) is the one place that names a vendor, so another provider
# is one more adapter. Plans, prices and credits are ours (config/blendolo/plans.yml); the provider sells a product
# id per paid plan and tells us, by signed webhook, what was paid. Credits are granted only from a verified webhook,
# never from the page the buyer comes back to.
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
      @provider ||= Dodo.new
    end

    # Whether payments take test cards (Dodo test mode). Pages say so.
    def test_mode?
      provider.test_mode?
    end
  end
end
