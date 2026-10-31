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

  def self.units_spent_on(date)
    where(day: date).sum(:units)
  end

  private
    def response_has_no_signed_urls
      errors.add(:response, "must not keep signed URLs") if response.to_json.match?(URL_WITH_QUERY)
    end
end
