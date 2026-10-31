# One paid call to the appearance provider: the cache key (operation + input_hash), the units it cost, the UTC day
# it counts towards, and the provider-neutral result. Signed URLs expire and grant access, so they're never stored.
class ProviderCall < ApplicationRecord
  URL_WITH_QUERY = %r{https?://[^\s"]*\?}

  belongs_to :kit, optional: true

  enum :status, { pending: 0, running: 1, done: 2, failed: 3 }, validate: true

  validates :operation, :input_hash, presence: true
  validates :input_hash, uniqueness: { scope: :operation }
  validate :response_has_no_signed_urls

  attribute :day, default: -> { Date.current }

  # An in-flight call older than this is taken as lost, and the next request calls again.
  STALE_AFTER = 5.minutes

  def self.units_spent_on(date)
    where(day: date).sum(:units)
  end

  # A call that may have cost units: everything but a refunded failure.
  scope :counted, -> { where.not(status: :failed).or(where("provider_calls.units > 0")) }

  def in_flight?
    (pending? || running?) && updated_at > STALE_AFTER.ago
  end

  # Takes this row for a new call, but only if nobody changed it since it was read. True when this caller won;
  # a concurrent request that loses must not start a second paid task.
  def claim!(kit:, units:)
    claimed = self.class.where(id:, status: self.class.statuses.fetch(status), updated_at:).update_all(
      kit_id: kit.id, status: self.class.statuses[:pending], units:, day: Date.current, response: {},
      updated_at: Time.current
    ) == 1
    reload if claimed
    claimed
  end

  private
    def response_has_no_signed_urls
      errors.add(:response, "must not keep signed URLs") if response.to_json.match?(URL_WITH_QUERY)
    end
end
