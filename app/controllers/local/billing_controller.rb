# The test checkout and portal of Billing::LocalTest, for local development without a Dodo key only
# (config.x.local_billing; the routes are drawn only then). Nothing is charged.
#   GET  /local/checkout   the test checkout for one plan
#   POST /local/checkout   "Pay": the payment's event goes to BillingEvent.receive!, the same code a verified webhook
#                          reaches (Webhooks::DodoController), then back to the page after paying
#   GET  /local/portal     the test portal: stop a Clinic plan
#   POST /local/portal     stops it the way the provider's "cancelled" webhook does
module Local
  class BillingController < ApplicationController
    include RequiresSignIn

    before_action { head :not_found unless Rails.configuration.x.local_billing && provider.is_a?(Billing::LocalTest) }
    before_action :set_plan, only: %i[checkout pay]

    def checkout
      private_page
      @success_url = url_from(params[:success_url]) || billing_success_path(plan: @plan.key)
      @cancel_url = url_from(params[:cancel_url]) || pricing_path
    end

    def pay
      BillingEvent.receive!(provider.payment_event(user: current_user, plan: @plan), provider: provider.name)
      redirect_to url_from(params[:success_url]) || billing_success_path(plan: @plan.key)
    end

    def portal
      private_page
      @renewing = renewing_subscription
      @return_url = url_from(params[:return_url]) || account_path
    end

    def cancel
      if (renewing = renewing_subscription)
        provider.cancel_subscription(renewing.subscription_id)
        redirect_to account_path, notice: "Your Clinic plan won't renew. Nothing was charged."
      else
        redirect_to account_path
      end
    end

    private
      def provider = Billing.provider

      def set_plan
        @plan = Billing::Plan.find(params[:plan]) or redirect_to(pricing_path)
      end

      def renewing_subscription
        renewing = BillingEvent.renewing_subscription_for(current_user)
        renewing if renewing&.provider == provider.name
      end

      def sign_in_origin
        pricing_path
      end
  end
end
