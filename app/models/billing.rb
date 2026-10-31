# Payments, behind one vendor-neutral interface (Billing::Provider). App code talks to this module, Billing::Plan and
# Billing::Event only; the vendor adapter (Billing::Dodo) is the one place that names a vendor, so another provider is
# one more adapter. Plans, prices and credits are ours (config/blendolo/plans.yml); the provider sells a product id
# per paid plan and tells us, by signed webhook, what was paid.
#
# Whose payment it is never comes from the webhook alone. Each account gets one customer at the provider, made by our
# server and kept as users.billing_customer_id; each checkout carries a Checkout's random token. A webhook pays an
# account only when its token resolves to a Checkout of that account AND its customer is that account's own customer
# (BillingEvent). "Manage" opens only the account's own customer's portal. Credits come only from a verified webhook,
# never from the page the buyer comes back to. In local development without a Dodo key, Billing::LocalTest stands in
# for Dodo and goes through the same checkout reference and customer match.
module Billing
  class Error < StandardError; end
  # A webhook whose signature or signature headers don't check out.
  class InvalidSignature < Error; end
  # A key, webhook secret or product id isn't set.
  class NotConfigured < Error; end
  # The provider's API failed: network, auth or an answer we can't use.
  class Unavailable < Error; end
  # There is nothing to manage yet: this account never started a checkout.
  class NoCustomer < Error; end
  # A Clinic checkout of this account is still opening in another tab: wait, then it can be picked up.
  class CheckoutOpening < Error; end

  # A paid Clinic period runs this long past its end, for a renewal payment that settles late.
  GRACE = 3.days

  class << self
    attr_writer :provider

    def provider
      @provider ||= Rails.configuration.x.local_billing ? LocalTest.new : Dodo.new
    end

    # Whether payments take test cards (Dodo test mode). Pages say so.
    def test_mode?
      provider.test_mode?
    end

    # The provider's checkout page for one of plan, for this account. An unfinished Clinic checkout from the last 30
    # minutes is picked up again instead of starting a second subscription.
    def start_checkout!(user, plan, success_url:, cancel_url:)
      checkout = claim_checkout(user, plan)
      return checkout.url if checkout.url

      url = provider.checkout_url(customer_id: customer_id!(user), plan:, reference: checkout.token, success_url:,
        cancel_url:)
      checkout.update!(url:)
      url
    rescue Error
      checkout.destroy if checkout&.url.nil? && checkout&.persisted?
      raise
    end

    # The account's own customer portal. Raises NoCustomer for an account that never started a checkout.
    def portal_url(user, return_url:)
      raise NoCustomer, "No customer yet" if user.billing_customer_id.blank?

      provider.portal_url(customer_id: user.billing_customer_id, return_url:)
    end

    # Stops every subscription of the account that still renews, now, before the account is deleted, so it is never
    # charged again. One the provider says had ended already counts as stopped. Raises Unavailable when the provider
    # can't be reached; nothing should be deleted then.
    def cancel_subscriptions!(user)
      BillingSubscription.where(user:).renewing.find_each do |subscription|
        provider.cancel_subscription(subscription.subscription_id)
        subscription.update!(status: "cancelled")
      end
    end

    # The account's customer at the provider: made once, by us, with the account's Google email. No lock is held
    # during the provider call; if two requests race, the first id saved wins and the other customer stays unused.
    def customer_id!(user)
      return user.billing_customer_id if user.billing_customer_id.present?

      made = provider.create_customer(email: user.email, name: user.name.presence || user.first_name)
      User.where(id: user.id, billing_customer_id: nil).update_all(billing_customer_id: made, updated_at: Time.current)
      user.reload.billing_customer_id
    rescue ActiveRecord::RecordNotUnique
      raise Unavailable, "the provider gave a customer id another account holds"
    end

    private
      # The Checkout to send the person to. For a Clinic plan, decided under a short lock on the account's row (no
      # network inside), so two tabs can't start two subscriptions: an unfinished checkout from the last 30 minutes
      # is picked up again, and one still opening means wait.
      def claim_checkout(user, plan)
        return Checkout.create!(user:, plan: plan.key, provider: provider.name) unless plan.subscription?

        user.with_lock do
          earlier = Checkout.where(user:, plan: plan.key, provider: provider.name, status: :pending,
            created_at: Checkout::RESUME_WITHIN.ago..).order(:id).last
          next earlier if earlier&.url
          raise CheckoutOpening, "a Clinic checkout is opening" if earlier && earlier.created_at > 1.minute.ago

          Checkout.create!(user:, plan: plan.key, provider: provider.name)
        end
      end
  end
end
