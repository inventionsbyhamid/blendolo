# Credits pay for live previews on a person's own face (config/blendolo/credits.yml). Every change is a CreditEntry
# row with the balance after it, written under a row lock on the user, so two requests at once never spend the same
# credit and the balance never goes below zero (a check constraint holds that too).
#
#   Credits.balance(user)                             credits left
#   Credits.grant!(user, amount, reason:, source:)    adds credits (signup_grant, pack_purchase, clinic_grant, admin)
#   Credits.debit!(user, amount, reason:, source:)    takes credits (render, transfer, admin), or raises Insufficient
#   Credits.refund!(user, amount, source:)            gives credits back (reason refund)
#
# Grants and refunds are safe to repeat: the same reason and source again returns the first entry and changes
# nothing. Render and transfer debits repeat on purpose, one per paid try.
#
# Previews: ProviderTracked#request! calls charge_render! after the unit guard and the cache, in the same transaction
# as the provider call's claim, before the start job; ProviderTracked#fail_call! calls refund_render! when the provider
# refused for sure. A cache hit, or a render that waits for someone else's call, costs nothing.
module Credits
  class Insufficient < StandardError; end

  # Where to get more. The pricing page lives at this path.
  PRICING_PATH = "/pricing".freeze

  module_function

  def balance(user)
    user.credit_entries.order(id: :desc).pick(:balance_after) || 0
  end

  def grant!(user, amount, reason:, source:)
    raise ArgumentError, "a grant adds credits" unless amount.is_a?(Integer) && amount.positive?

    record!(user, amount, reason:, source:)
  end

  def debit!(user, amount, reason:, source:)
    raise ArgumentError, "a debit takes credits" unless amount.is_a?(Integer) && amount.positive?

    record!(user, -amount, reason:, source:)
  end

  def refund!(user, amount, source:)
    grant!(user, amount, reason: :refund, source:)
  end

  def cost(operation)
    config.fetch(:costs).fetch(operation.to_sym)
  end

  def signup_amount
    config.fetch(:signup_grant)
  end

  # A look on your own face: the classic and the easy render.
  def look_cost
    cost(:makeup) * 2
  end

  # The free credits for a new account, once per Google account (SignupGrant), even after the account is deleted
  # and made again. Nil when they were given before.
  def grant_signup!(user)
    digest = SignupGrant.digest_for(user)
    return if SignupGrant.exists?(account_digest: digest)

    SignupGrant.transaction do
      SignupGrant.create!(account_digest: digest)
      grant!(user, signup_amount, reason: :signup_grant, source: "user:#{user.id}")
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Pays for the provider call a render is about to start, from the account its kit is in.
  def charge_render!(render)
    user = render.kit.user or raise Insufficient, "the kit is in no account"

    debit!(user, cost(render.operation), reason: render.transfer? ? :transfer : :render, source: render_source(render))
  end

  # Gives back what the render's latest try took. Once per try, however often the failure is reported.
  def refund_render!(render)
    user = render.kit&.user or return
    debit = user.credit_entries.where(reason: CreditEntry::REPEATABLE, source: render_source(render)).order(:id).last
    return unless debit

    refund!(user, -debit.delta, source: "credit_entry:#{debit.id}")
  end

  def render_source(render)
    "render:#{render.id}"
  end

  def config
    Rails.application.config_for(:"blendolo/credits")
  end

  def record!(user, delta, reason:, source:)
    reason = reason.to_s
    source = source&.to_s
    user.with_lock do
      earlier = CreditEntry.find_by(reason:, source:) if source && CreditEntry.once_per_source?(reason)
      next earlier if earlier

      after = balance(user) + delta
      raise Insufficient, "#{-delta} credits needed, #{after - delta} left" if after.negative?

      user.credit_entries.create!(delta:, reason:, source:, balance_after: after)
    end
  rescue ActiveRecord::RecordNotUnique
    # The same grant for another user's row at the same moment (the index is per reason and source).
    CreditEntry.find_by!(reason:, source:)
  end
  private_class_method :record!
end
