# One verified payment provider webhook (a Billing::Event), stored once by (provider, event_id) and applied in the same
# transaction: a retried or replayed delivery changes nothing, and a failure part way leaves nothing behind, so the
# provider's retry applies it again.
#
# Whose it is: a payment or a new subscription belongs to an account only when its reference resolves to a Checkout
# that account started AND its customer is that account's own customer (users.billing_customer_id). Later events of a
# subscription follow the subscription (BillingSubscription), and refunds and disputes follow the payment they take
# back; the customer must still match. Anything else (a static payment link, forged metadata, another customer, a
# product that isn't ours) is stored as unmatched, logged, and changes nothing: `bin/rails billing:unmatched` lists
# them for the owner.
#
#   pack_paid               adds the pack's credits x quantity, once per payment
#   subscription_active     adds the Clinic credits x quantity, once per paid period (a period's first payment can
#   subscription_renewed    send both events), and keeps the Clinic plan to the period end plus Billing::GRACE
#   subscription_updated    follows the subscription: a cancellation booked for the period end stops "renewing"
#   subscription_past_due   a renewal payment is being retried: the plan runs to its paid end plus the grace
#   subscription_cancelled  it won't renew; the plan runs to its paid end
#   subscription_expired    ends the plan now (unless another subscription of the account still pays for it)
#   refund, dispute         takes back what is left of that payment's credits (never below zero), once per refund or
#                           dispute; partial refunds take back their share, counted over all refunds of the payment.
#                           A Clinic payment taken back also ends the plan now and cancels the subscription at the
#                           provider (a job, after the commit), so it is never charged again
#   dispute_won             gives back what that dispute took, once
# clinic_until only moves forward, except on an expiry, a refund or a dispute. State follows the provider's event
# times, not the order deliveries arrive.
class BillingEvent < ApplicationRecord
  belongs_to :user, optional: true

  enum :kind, { pack_paid: 0, subscription_active: 1, subscription_renewed: 2, subscription_cancelled: 3,
    subscription_expired: 4, refund: 5, subscription_updated: 6, subscription_past_due: 7, dispute: 8, dispute_won: 9 },
    validate: { allow_nil: true }
  enum :status, { applied: 0, ignored: 1, unmatched: 2 }, validate: true

  # What the account page lists, newest first: payments that added credits, refunds, and each dispute once (the event
  # that took its credits back, and the one that gave them back if the dispute was won).
  scope :purchases, -> { where.not(credits: nil).or(where(kind: :refund, status: :applied)).order(created_at: :desc, id: :desc) }

  # Stores and applies a verified event; the row already stored when the provider sends it again.
  def self.receive!(event, provider:)
    row = transaction do
      create!(provider:, event_id: event.id, event_type: event.name.presence || "unknown", kind: event.type,
        reference: event.reference, plan: event.plan&.key, customer_id: event.customer_id,
        subscription_id: event.subscription_id, payment_id: event.payment_id, amount_cents: event.amount_cents,
        currency: event.currency, period_end: event.period_end, occurred_at: event.occurred_at,
        payload: event.payload).tap { |created| created.apply!(event) }
    end
    # Network calls never run inside the transaction: subscriptions to stop go to a job once it has committed.
    row.to_cancel.each { |subscription_id| BillingCancelJob.perform_later(provider, subscription_id) }
    row
  rescue ActiveRecord::RecordNotUnique
    find_by!(provider:, event_id: event.id)
  end

  # Subscriptions this event says to stop at the provider: a Clinic payment taken back, or one paid for an account
  # that is gone or isn't the checkout's.
  def to_cancel
    @to_cancel ||= []
  end

  def apply!(event)
    @event = event
    note = settle
    self.status = :ignored if kind.nil?
    if unmatched?
      Rails.logger.warn("[billing] unmatched #{provider} event #{event_id} (#{event_type}): #{note}")
    end
    self.note = note
    save!
  end

  def plan_record
    Billing::Plan.find(plan) if plan
  end

  private
    attr_reader :event

    def settle
      return "not an event we act on" unless kind
      return unmatched("not one of our products") if plan_record.nil? && !money_back? && !dispute_won?

      if pack_paid? then pay_pack
      elsif money_back? then take_back
      elsif dispute_won? then give_back
      else follow_subscription
      end
    end

    def money_back? = refund? || dispute?

    def unmatched(why)
      self.status = :unmatched
      self.user = nil
      why
    end

    # The account a new payment or subscription belongs to: its Checkout's account, if the paying customer is that
    # account's own.
    def account_from_checkout
      checkout = Checkout.find_by(token: reference, provider:) if reference.present?
      account = checkout&.user
      account if account&.billing_customer_id.present? && account.billing_customer_id == customer_id
    end

    def pay_pack
      return "a subscription product paid as a pack" if plan_record.subscription?

      self.user = account_from_checkout or return unmatched("no checkout of ours for this customer")
      Checkout.where(token: reference, provider:).each(&:paid!)
      check_amount
      grant(:pack_purchase, source: "#{provider}:#{payment_id}")
    end

    def follow_subscription
      return "a pack product as a subscription" unless plan_record.subscription?

      subscription = BillingSubscription.find_by(provider:, subscription_id:)
      self.user = subscription&.user || account_from_checkout
      unless user && user.billing_customer_id == customer_id
        stop_orphan(subscription)
        return unmatched("no checkout of ours for this customer")
      end

      subscription ||= start_subscription
      current = subscription.follow!(event)
      Rails.logger.warn("[billing] account #{user_id} has a second Clinic subscription #{subscription_id}") if second_subscription?(subscription)

      case kind
      when "subscription_active", "subscription_renewed" then pay_period(subscription)
      when "subscription_expired" then current ? (end_clinic!(except: subscription) && nil) : "older than what we have"
      else current ? nil : "older than what we have"
      end
    end

    # A subscription paid for through a checkout of ours whose account is gone, or by a customer that isn't the
    # checkout's, is stopped at once so it isn't charged again. One with no reference of ours at all is only listed
    # (bin/rails billing:unmatched): stopping those would end real plans if a delivery ever lacked our metadata.
    def stop_orphan(subscription)
      return unless subscription_id && Billing::Event::PAID_PERIODS.include?(kind.to_sym)

      checkout = Checkout.find_by(token: reference, provider:) if reference.present?
      to_cancel << subscription_id if checkout || (subscription && subscription.user_id.nil?)
    end

    def start_subscription
      Checkout.where(token: reference, provider:).each(&:paid!)
      # A savepoint of its own, so losing the insert race to a second delivery leaves this transaction usable.
      BillingSubscription.transaction(requires_new: true) do
        BillingSubscription.create!(provider:, subscription_id:, user:, plan:, status: event.subscription_status || "active")
      end
    rescue ActiveRecord::RecordNotUnique
      BillingSubscription.find_by!(provider:, subscription_id:)
    end

    def second_subscription?(subscription)
      BillingSubscription.where(user:).standing.where.not(id: subscription.id).exists?
    end

    def pay_period(subscription)
      return "no period end" unless period_end

      extend_clinic!(period_end + Billing::GRACE)
      check_amount
      grant(:clinic_grant, source: "#{provider}:#{subscription_id}:#{period_end.utc.to_date.iso8601}")
    end

    # A refund or a dispute: follows the payment it takes back.
    def take_back
      paid = original_payment or return unmatched("no payment of ours for #{payment_id}")
      self.user = paid.user or return unmatched("the account is gone")
      return unmatched("another customer") if customer_id.present? && customer_id != user.billing_customer_id

      self.plan ||= paid.plan
      if paid.plan_record&.subscription?
        subscription = BillingSubscription.find_by(provider:, subscription_id: paid.subscription_id)
        stop_refunded(subscription)
        ended = end_clinic!(except: subscription)
      end
      taken = claw_back(paid)
      [ taken, ("the Clinic plan ended now" if ended) ].compact.join("; ").presence
    end

    # The money for a Clinic month went back: the plan stops here now and at the provider after the commit, so the
    # account can start a new one straight away and is never charged again for this one.
    def stop_refunded(subscription)
      return unless subscription

      subscription.update!(status: "cancelled", cancel_at_period_end: true)
      to_cancel << subscription.subscription_id
    end

    # A dispute the business won: what it took back comes back, once.
    def give_back
      taken = BillingEvent.where(provider:, kind: :dispute, status: :applied, payment_id:).where("credits < 0")
        .where("payload -> 'data' ->> 'dispute_id' = ?", event.money_back_id.to_s).first
      return "nothing was taken back for this dispute" unless taken

      self.user = taken.user or return unmatched("the account is gone")
      self.plan = taken.plan
      entry = Credits.grant!(user, -taken.credits, reason: :refund, source: "#{provider}:dispute_won:#{event.money_back_id}")
      return "credits already given back" unless entry.previously_new_record?

      self.credits = -taken.credits
      nil
    end

    # The payment this refund or dispute is about: the pack payment, or the Clinic period it paid for.
    def original_payment
      BillingEvent.where(provider:, payment_id:, status: :applied).where("credits > 0").order(:id).first ||
        clinic_period_for(payment_id)
    end

    def clinic_period_for(payment)
      subscription = BillingEvent.where(provider:, payment_id: payment).where.not(subscription_id: nil).pick(:subscription_id)
      return unless subscription

      # The first period's start event carries no payment id: the earliest paid period is the best match.
      BillingEvent.where(provider:, subscription_id: subscription, status: :applied).where("credits > 0").order(:id).first
    end

    # Refunds take back their share of the payment's credits, counted over every refund of it so far (refunded / paid
    # x granted, rounded up); a dispute takes back all of it. Never more than the payment granted, never below zero.
    def claw_back(paid)
      key = "#{provider}:#{paid.payment_id || paid.event_id}"
      already = user.credit_entries.where(reason: "clawback").where("source LIKE ?", "#{key}:%").sum(:delta).abs
      wanted = (paid.credits * share_back(paid)).ceil - already
      return "credits already taken back" unless wanted.positive?

      entry = Credits.claw_back!(user, wanted, source: "#{key}:#{event.money_back_id || event_id}")
      taken = entry ? -entry.delta : 0
      self.credits = -taken
      taken < wanted ? "took back #{taken} of #{wanted} credits; the rest were spent" : nil
    end

    def share_back(paid)
      return 1 unless refund? && amount_cents && paid.amount_cents.to_i.positive?

      refunded = BillingEvent.applied.where(provider:, kind: :refund, payment_id:).where.not(id:).sum(:amount_cents) + amount_cents
      [ refunded.fdiv(paid.amount_cents), 1 ].min
    end

    def grant(reason, source:)
      amount = plan_record.credits * event.quantity
      entry = Credits.grant!(user, amount, reason:, source:)
      return "credits already added for #{source}" unless entry.previously_new_record?

      self.credits = amount
      nil
    end

    # Logged, never refused: the provider may show a local price, or add tax.
    def check_amount
      expected = plan_record.price_cents * event.quantity
      return if event.currency.to_s.upcase == "USD" && (event.net_cents.nil? || event.net_cents == expected)

      Rails.logger.info("[billing] #{event_id}: paid #{event.net_cents.inspect} #{event.currency} for #{expected} USD")
    end

    # Moves clinic_until forward only.
    def extend_clinic!(to)
      User.where(id: user.id).update_all([ "clinic_until = GREATEST(COALESCE(clinic_until, :to), :to)", { to: } ])
      user.reload
    end

    # Ends the plan now, unless another subscription of the account is still paid up: then it runs to that one's end.
    # True when the plan ended.
    def end_clinic!(except:)
      others = BillingSubscription.where(user:).standing.where.not(id: except&.id).where(period_end: Time.current..)
      ends = others.maximum(:period_end)&.+(Billing::GRACE) || Time.current
      user.update!(clinic_until: ends)
      ends <= Time.current
    end
end
