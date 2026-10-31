# A read-only link to a kit's routine for someone who helps: scoped, expiring and revocable.
class Share < ApplicationRecord
  include ExampleReadOnly
  LIFETIME = 30.days

  belongs_to :kit

  has_secure_token :token

  enum :audience, { helper: 0, family: 1, therapist: 2 }, validate: true
  enum :scope, { routine_only: 0, routine_and_photos: 1 }, validate: true

  scope :live, -> { where(revoked_at: nil).where.not(expires_at: ..Time.current) }

  attribute :expires_at, default: -> { LIFETIME.from_now }

  def live?
    revoked_at.nil? && expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
