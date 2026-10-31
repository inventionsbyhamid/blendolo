# Stops a subscription at the payment provider after the webhook that asked for it has committed (a Clinic month paid
# back, or a subscription paid for an account that is gone), so it is never charged again. Retried while the provider
# can't be reached; one that had ended already counts as stopped.
class BillingCancelJob < ApplicationJob
  queue_as :default

  retry_on Billing::Unavailable, Billing::NotConfigured, wait: :polynomially_longer, attempts: 10

  def perform(provider_name, subscription_id)
    provider = Billing.provider
    return unless provider.name == provider_name

    provider.cancel_subscription(subscription_id)
    BillingSubscription.where(provider: provider_name, subscription_id:).update_all(status: "cancelled", updated_at: Time.current)
  end
end
