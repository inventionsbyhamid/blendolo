# POST /billing/portal: "Manage" opens the payment provider's customer portal for this account: receipts, the card,
# and cancelling the Clinic plan.
class BillingPortalsController < ApplicationController
  include RequiresSignIn

  rate_limit to: 10, within: 1.minute, with: -> { too_many_requests }

  def create
    redirect_to Billing.portal_url(current_user, return_url: account_url), allow_other_host: true
  rescue Billing::NoCustomer
    redirect_to account_path, notice: "There is nothing to manage yet. Your purchases show here once you buy."
  rescue Billing::Error => e
    Rails.logger.error("[billing] portal failed: #{e.class.name.demodulize}: #{e.message}")
    redirect_to account_path, notice: "Payments aren't working right now. Please try again in a few minutes."
  end

  private
    def sign_in_origin
      account_path
    end
end
