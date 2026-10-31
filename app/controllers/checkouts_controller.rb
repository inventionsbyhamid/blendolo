# Buying credits:
#   POST /checkout (plan)    sends a signed-in person to the payment provider's checkout for one plan
#   GET  /billing/success    where they come back: shows the credits once the provider's webhook has added them
# Credits come only from the provider's signed webhook (Webhooks::DodoController), never from this return page.
class CheckoutsController < ApplicationController
  include RequiresSignIn

  rate_limit to: 10, within: 1.minute, only: :create, with: -> { too_many_requests }

  # How far back the return page looks for this checkout's credits when the session doesn't say when it began.
  LOOK_BACK = 1.hour

  def create
    plan = Billing::Plan.find(params[:plan]) or return redirect_to(pricing_path)
    return redirect_to(clinic_path, notice: "Your Clinic plan is already on.") if plan.subscription? && clinic_taken?

    url = Billing.start_checkout!(current_user, plan, success_url: billing_success_url(plan: plan.key),
      cancel_url: pricing_url(anchor: plan.key.dasherize))
    session[:checkout_started_at] = Time.current.to_i
    redirect_to url, allow_other_host: true
  rescue Billing::Error => e
    Rails.logger.error("[billing] checkout failed: #{e.class.name.demodulize}: #{e.message}")
    redirect_to pricing_path, notice: "Payments aren't working right now, so nothing was charged. Please try again in a few minutes."
  end

  def success
    # The provider adds the buyer's email and its own ids to this address: drop them from the address bar, history
    # and every poll.
    extra = request.query_parameters.keys - %w[plan status]
    return redirect_to(billing_success_path(params.permit(:plan, :status).to_h.symbolize_keys)) if extra.any?

    private_page
    @plan = Billing::Plan.find(params[:plan])
    @failed = params[:status].to_s.in?(%w[failed cancelled])
    since = session[:checkout_started_at] ? Time.zone.at(session[:checkout_started_at].to_i) : LOOK_BACK.ago
    @arrived = BillingEvent.applied.where(user: current_user, plan: @plan&.key).where("credits > 0")
      .where(created_at: since..).order(:id).last
    @credits = Credits.balance(current_user)
    kit = remembered_kit
    @next_path = kit&.purge_after&.future? ? kit_looks_path(kit) : start_path
  end

  private
    # One Clinic plan per account: not while one is on, or a subscription of the account still stands.
    def clinic_taken?
      current_user.clinic? || BillingSubscription.where(user: current_user).standing.exists?
    end

    def sign_in_origin
      plan = Billing::Plan.find(params[:plan])
      plan ? pricing_path(anchor: plan.key.dasherize) : pricing_path
    end
end
