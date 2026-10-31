# One verified payment provider webhook (a Billing::Event), stored once by (provider, event_id) and applied in the same
# transaction: a retried or replayed delivery changes nothing, and a failure part way leaves nothing behind, so the
# provider's retry applies it again.
#
#   pack_paid               adds the pack's credits, once per payment
#   subscription_active     adds the clinic's monthly credits, once per paid period (a period's first payment can
#   subscription_renewed    send both events), and keeps the clinic plan until the period ends, plus a day's grace
#   subscription_cancelled  keeps the clinic plan until the paid period ends, then it stops
#   subscription_expired    ends the clinic plan now
#   refund                  noted only: credits already added stay (a balance never goes below zero)
#
# The account comes from the user id our checkout put in the metadata, else from an earlier event for the same
# subscription or payment. note says why an event changed nothing.
class BillingEvent < ApplicationRecord
  GRACE = 1.day
  CLINIC_STARTS = %w[subscription_active subscription_renewed].freeze

  belongs_to :user, optional: true

  enum :kind, { pack_paid: 0, subscription_active: 1, subscription_renewed: 2, subscription_cancelled: 3,
    subscription_expired: 4, refund: 5 }, validate: { allow_nil: true }

  # What the account page lists: payments that added credits, and refunds. Newest first.
  scope :purchases, -> { where.not(credits: nil).or(where(kind: :refund)).order(created_at: :desc, id: :desc) }

  # Stores and applies a verified event; the row already stored when the provider sends it again.
  def self.receive!(event, provider:)
    transaction do
      create!(provider:, event_id: event.id, event_type: event.name.presence || "unknown", kind: event.type,
        plan: event.plan&.key, customer_id: event.customer_id, subscription_id: event.subscription_id,
        payment_id: event.payment_id, amount_cents: event.amount_cents, currency: event.currency,
        period_end: event.period_end, payload: event.payload).tap { |row| row.apply!(event.user_id) }
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(provider:, event_id: event.id)
  end

  # The provider's customer id for an account's portal: the latest one its payments used.
  def self.customer_id_for(user, provider:)
    where(user:, provider:).where.not(customer_id: nil).order(:id).last&.customer_id
  end

  # The clinic subscription an account is on: the one its latest clinic payment was for.
  def self.clinic_subscription_for(user)
    where(user:, kind: CLINIC_STARTS).where.not(subscription_id: nil).order(:id).last
  end

  # That subscription while it will still renew (not cancelled or expired since its latest payment), or nil.
  def self.renewing_subscription_for(user)
    current = clinic_subscription_for(user) or return
    ended = where(user:, subscription_id: current.subscription_id, kind: %i[subscription_cancelled subscription_expired])
      .where("id > ?", current.id).exists?
    current unless ended
  end

  def apply!(user_id)
    self.user = account_for(user_id)
    self.note = settle
    save!
  end

  def plan_record
    Billing::Plan.find(plan) if plan
  end

  private
    def account_for(user_id)
      user = User.find_by(id: user_id) if user_id.to_s.match?(/\A\d+\z/)
      user || earlier_account
    end

    def earlier_account
      same = BillingEvent.where(provider:).where.not(user_id: nil).where.not(id:)
      match = same.where(subscription_id:).where.not(subscription_id: nil).or(same.where(payment_id:).where.not(payment_id: nil))
      match.order(:id).last&.user
    end

    def settle
      return "not an event we act on" unless kind
      return "no account for this payment" unless user
      return "noted; credits already added stay" if refund?
      return "not one of our products" unless plan_record

      send(:"apply_#{kind}")
    end

    def apply_pack_paid
      return "a subscription product paid as a pack" if plan_record.subscription?

      grant(:pack_purchase, source: "#{provider}:#{payment_id}")
    end

    def apply_subscription_active
      return "a pack product as a subscription" unless plan_record.subscription?
      return "no period end" unless period_end

      ends = period_end + GRACE
      user.update!(clinic_until: ends) if user.clinic_until.nil? || user.clinic_until < ends
      grant(:clinic_grant, source: "#{provider}:#{subscription_id}:#{period_end.utc.to_date.iso8601}")
    end
    alias_method :apply_subscription_renewed, :apply_subscription_active

    def apply_subscription_cancelled
      return "not the account's clinic subscription" unless current_subscription?
      return "no period end; the plan runs to its date" unless period_end

      user.update!(clinic_until: period_end) if user.clinic_until.nil? || user.clinic_until > period_end
      nil
    end

    def apply_subscription_expired
      return "not the account's clinic subscription" unless current_subscription?

      user.update!(clinic_until: Time.current) if user.clinic?
      nil
    end

    # A late event for an old subscription must not end a newer one.
    def current_subscription?
      current = BillingEvent.where(provider:, user:, kind: CLINIC_STARTS).where.not(id:).order(:id).last
      current.nil? || current.subscription_id == subscription_id
    end

    def grant(reason, source:)
      entry = Credits.grant!(user, plan_record.credits, reason:, source:)
      return "credits already added for #{source}" unless entry.previously_new_record?

      self.credits = plan_record.credits
      nil
    end
end
