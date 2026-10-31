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
#                           dispute; a Clinic payment taken back also ends the plan now
# clinic_until only moves forward, except on an expiry, a refund or a dispute. State follows the provider's event
# times, not the order deliveries arrive.
class BillingEvent < ApplicationRecord
  belongs_to :user, optional: true

  enum :kind, { pack_paid: 0, subscription_active: 1, subscription_renewed: 2, subscription_cancelled: 3,
    subscription_expired: 4, refund: 5, subscription_updated: 6, subscription_past_due: 7, dispute: 8 },
    validate: { allow_nil: true }
  enum :status, { applied: 0, ignored: 1, unmatched: 2 }, validate: true

  # What the account page lists: payments that added credits, and money taken back. Newest first.
  scope :purchases, -> { where.not(credits: nil).or(where(kind: %i[refund dispute], status: :applied)).order(created_at: :desc, id: :desc) }

  # Stores and applies a verified event; the row already stored when the provider sends it again.
  def self.receive!(event, provider:)
    transaction do
      create!(provider:, event_id: event.id, event_type: event.name.presence || "unknown", kind: event.type,
        reference: event.reference, plan: event.plan&.key, customer_id: event.customer_id,
        subscription_id: event.subscription_id, payment_id: event.payment_id, amount_cents: event.amount_cents,
        currency: event.currency, period_end: event.period_end, occurred_at: event.occurred_at,
        payload: event.payload).tap { |row| row.apply!(event) }
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(provider:, event_id: event.id)
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
      return unmatched("not one of our products") if plan_record.nil? && !money_back?

      if pack_paid? then pay_pack
      elsif money_back? then take_back
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
      Checkout.where(token: reference, provider:).update_all(status: Checkout.statuses[:paid], updated_at: Time.current)
      check_amount
      grant(:pack_purchase, source: "#{provider}:#{payment_id}")
    end

    def follow_subscription
      return "a pack product as a subscription" unless plan_record.subscription?

      subscription = BillingSubscription.find_by(provider:, subscription_id:)
      self.user = subscription&.user || account_from_checkout
      return unmatched("no checkout of ours for this customer") unless user && user.billing_customer_id == customer_id

      subscription ||= start_subscription
      current = subscription.follow!(event)
      Rails.logger.warn("[billing] account #{user_id} has a second Clinic subscription #{subscription_id}") if second_subscription?(subscription)

      case kind
      when "subscription_active", "subscription_renewed" then pay_period(subscription)
      when "subscription_expired" then current ? (end_clinic!(except: subscription) && nil) : "older than what we have"
      else current ? nil : "older than what we have"
      end
    end

    def start_subscription
      Checkout.where(token: reference, provider:).update_all(status: Checkout.statuses[:paid], updated_at: Time.current)
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
        ended = end_clinic!(except: BillingSubscription.find_by(provider:, subscription_id: paid.subscription_id))
      end
      taken = claw_back(paid)
      [ taken, ("the Clinic plan ended now" if ended) ].compact.join("; ").presence
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

    def claw_back(paid)
      share = amount_cents && paid.amount_cents.to_i.positive? ? [ amount_cents.fdiv(paid.amount_cents), 1 ].min : 1
      already = user.credit_entries.where(reason: "clawback").where("source LIKE ?", "#{provider}:#{paid.payment_id || paid.event_id}:%").sum(:delta).abs
      wanted = (paid.credits * share).ceil - already
      return "credits already taken back" unless wanted.positive?

      entry = Credits.claw_back!(user, wanted, source: "#{provider}:#{paid.payment_id || paid.event_id}:#{event.money_back_id || event_id}")
      taken = entry ? -entry.delta : 0
      self.credits = -taken if taken.positive?
      taken < wanted ? "took back #{taken} of #{wanted} credits; the rest were spent" : nil
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
