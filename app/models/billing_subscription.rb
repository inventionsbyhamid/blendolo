# A subscription at the payment provider, for one account. Its state follows the provider's webhooks in the order
# they happened (event_at), never the order they arrived, so a late or retried delivery can't turn it back.
#   active, past_due, on_hold   still renewing (past_due and on_hold: a renewal payment is being retried)
#   cancelled, expired, failed  it won't renew
# cancel_at_period_end: the customer asked to stop at the end of the paid period; it won't renew either.
class BillingSubscription < ApplicationRecord
  STANDING = %w[active past_due on_hold].freeze
  ENDED = %w[cancelled expired failed].freeze

  belongs_to :user, optional: true

  scope :standing, -> { where(status: STANDING) }
  scope :renewing, -> { standing.where(cancel_at_period_end: false) }

  def renewing?
    STANDING.include?(status) && !cancel_at_period_end
  end

  def plan_record
    Billing::Plan.find(plan)
  end

  # Takes the state from an event unless a later one was already applied. True when it was taken.
  def follow!(event)
    return false if event_at && event.occurred_at && event.occurred_at < event_at

    attributes = { event_at: event.occurred_at || event_at }
    attributes[:status] = event.subscription_status if event.subscription_status.present?
    attributes[:cancel_at_period_end] = event.cancel_at_period_end unless event.cancel_at_period_end.nil?
    attributes[:period_end] = event.period_end if event.period_end
    update!(attributes)
    true
  end
end
