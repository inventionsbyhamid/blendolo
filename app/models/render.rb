# A makeup preview on today's photo. effects is the provider-neutral list from Looks::EffectsBuilder; a transfer
# copies the look on reference_photo instead. external_id is the provider's task id while it runs.
class Render < ApplicationRecord
  include ExampleReadOnly
  include ProviderTracked

  belongs_to :kit
  belongs_to :photo
  belongs_to :reference_photo, class_name: "Photo", optional: true

  enum :kind, { classic: 0, easy: 1, tweak: 2, transfer: 3, step: 4 }, validate: true
  enum :status, { pending: 0, running: 1, done: 2, failed: 3 }, validate: true

  has_one_attached :result

  validates :reference_photo, presence: true, if: :transfer?

  # Refusals that signing in or more credits lift: the next "Show it on my face" asks again (Previews.for).
  PAYMENT_REFUSALS = %w[sign_in no_credits].freeze

  def awaiting_payment?
    failed? && PAYMENT_REFUSALS.include?(failure_reason)
  end
end
