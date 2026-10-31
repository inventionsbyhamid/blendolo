# A checkout our server started for an account (Billing.start_checkout!). Its random token is the reference the
# provider carries in the session's metadata and sends back on every webhook for that payment or subscription, so a
# payment is tied to the account that started it. pending until the provider says it was paid.
class Checkout < ApplicationRecord
  # An unfinished Clinic checkout this recent is picked up again instead of starting a second subscription.
  RESUME_WITHIN = 30.minutes

  belongs_to :user, optional: true
  has_secure_token :token, length: 32

  # expired: its account was deleted, or it was never finished. A payment for it pays nobody; a subscription paid
  # for it is stopped at once (BillingEvent).
  enum :status, { pending: 0, paid: 1, expired: 2 }, validate: true

  validates :provider, :plan, presence: true

  # The provider's page opens with the buyer's name and email filled in: it is kept only while it can be resumed.
  def paid!
    update!(status: :paid, url: nil)
  end

  # Old pages are forgotten (PurgeExpiredKitsJob), and a deleted account's checkouts expire with it.
  def self.forget_old_pages!
    where(created_at: ...RESUME_WITHIN.ago).where.not(url: nil).update_all(url: nil, updated_at: Time.current)
  end

  def self.expire_for!(user)
    where(user:).update_all(status: statuses[:expired], url: nil, updated_at: Time.current)
  end
end
