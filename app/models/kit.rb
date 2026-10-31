# One person's private workspace, reached by its token link: the token is the key. A kit may be in an account (user),
# which pays for its previews on the person's own face; a guest kit joins the account when its owner signs in.
class Kit < ApplicationRecord
  # The "Your hands" questions, in the order they're asked. Each answer is 0..2:
  # tremor, pinch, fatigue: no / a little or sometimes / yes. one_hand: both / mostly left / mostly right.
  # near_vision: no / a little / yes.
  HAND_QUESTIONS = %i[tremor pinch one_hand fatigue near_vision].freeze
  ANSWERS = 0..2
  RETENTION_DAYS = [ 7, 30 ].freeze

  # Example kits are shared by every visitor, so they only take visits (activity); everything else is refused with
  # this message, for the UI to show. Examples builds them with building_example set.
  EXAMPLE_READ_ONLY = "This is an example, so it can't be changed. Start your own to try it."
  EXAMPLE_ACTIVITY = %w[last_active_at purge_after updated_at].freeze

  class ReadOnlyExample < StandardError; end

  attr_accessor :building_example

  has_secure_token :token

  belongs_to :user, optional: true

  # Renders before photos: renders point at photos.
  has_many :renders, dependent: :destroy
  has_many :photos, dependent: :destroy
  has_many :shares, dependent: :delete_all
  # Calls stay for the daily unit count; the database clears their kit_id.
  has_many :provider_calls, dependent: nil

  enum :path, { self_use: 0, helper: 1, example: 2 }, validate: true

  # A short name, for accounts with several kits (a clinic's clients).
  LABEL_MAX = 40
  normalizes :label, with: ->(label) { label.squish.presence }
  validates :label, length: { maximum: LABEL_MAX }

  validates(*HAND_QUESTIONS, inclusion: { in: ANSWERS }, allow_nil: true)
  # "My hands today": 0 steady, 1 a bit shaky, 2 very shaky or stiff. Sets target sizes and the repeat-tap guard.
  validates :hands_today, inclusion: { in: ANSWERS }
  validates :retention_days, inclusion: { in: RETENTION_DAYS }

  validate :example_stays_as_built, on: :update

  before_save :schedule_purge

  # The answers as Ease::HandProfile takes them. A question not answered yet counts as the first answer
  # (no / both), which adds no weight.
  def hand_answers
    HAND_QUESTIONS.index_with { |question| public_send(question).to_i }
  end

  def hand_profile
    Ease::HandProfile.new(**hand_answers)
  end

  def read_only_example?
    (example? || path_in_database == "example") && !building_example
  end

  def owned_by?(user)
    user.present? && user_id == user.id
  end

  # Links use the private token: /k/<token>.
  def to_param
    token
  end

  # Called on every visit: retention counts from the last activity.
  def touch_activity!
    update!(last_active_at: Time.current)
  end

  # "Delete everything" (refused for a living example kit), and retention: the files and their resized variants go
  # now rather than in a later purge job, then every row. Provider calls stay, without the kit and emptied of
  # results, for the daily unit count (PurgeExpiredKitsJob deletes them after two days).
  def destroy_everything!
    raise ReadOnlyExample, EXAMPLE_READ_ONLY if read_only_example? && purge_after.future?

    files = photos.includes(image_attachment: :blob).map(&:image) +
      renders.includes(result_attachment: :blob).map(&:result)
    variants = files.select(&:attached?).flat_map do |file|
      file.blob.variant_records.includes(image_attachment: :blob).map(&:image)
    end
    (variants + files).each(&:purge)
    provider_calls.update_all(response: {}, updated_at: Time.current)
    destroy!
  end

  private
    def example_stays_as_built
      errors.add(:base, EXAMPLE_READ_ONLY) if read_only_example? && (changed - EXAMPLE_ACTIVITY).any?
    end

    def schedule_purge
      self.last_active_at ||= Time.current
      self.purge_after = last_active_at + retention_days.days
    end
end
