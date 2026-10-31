# A checkout our server started for an account (Billing.start_checkout!). Its random token is the reference the
# provider carries in the session's metadata and sends back on every webhook for that payment or subscription, so a
# payment is tied to the account that started it. pending until the provider says it was paid.
class Checkout < ApplicationRecord
  # An unfinished Clinic checkout this recent is picked up again instead of starting a second subscription.
  RESUME_WITHIN = 30.minutes

  belongs_to :user, optional: true
  has_secure_token :token, length: 32

  enum :status, { pending: 0, paid: 1 }, validate: true

  validates :provider, :plan, presence: true

  # The account's unfinished checkout for this plan from the last RESUME_WITHIN, with its page, or nil.
  def self.resumable(user, plan)
    where(user:, plan: plan.key, status: :pending, created_at: RESUME_WITHIN.ago..).where.not(url: nil).order(:id).last
  end
end
