# POST /webhooks/dodo: the payment provider says something was paid, renewed, cancelled or refunded. The signature on
# the raw body is checked before anything is read (401 when it fails); then the event is stored once by its id and
# applied in one transaction (BillingEvent.receive!), so the provider gets 200 for a delivery it sends again, and a
# non-2xx (so it retries) when something failed part way. Events we don't act on are stored and answered 200.
module Webhooks
  class DodoController < ActionController::API
    # The provider retries a refused delivery, so this only stops a flood.
    rate_limit to: 120, within: 1.minute

    def create
      provider = Billing.provider
      BillingEvent.receive!(provider.parse_webhook(request), provider: provider.name)
      head :ok
    rescue Billing::InvalidSignature => e
      Rails.logger.warn("[billing] webhook rejected: #{e.message}")
      head :unauthorized
    rescue Billing::NotConfigured => e
      # Not a 4xx: the provider keeps retrying until the secret is set.
      Rails.logger.error("[billing] webhook can't be checked: #{e.message}")
      head :service_unavailable
    end
  end
end
