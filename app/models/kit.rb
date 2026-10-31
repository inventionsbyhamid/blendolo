# One person's private workspace, reached by its token link. No account: the token is the key.
class Kit < ApplicationRecord
  # The "Your hands" questions, in the order they're asked. Each answer is 0..2:
  # tremor, pinch, fatigue: no / a little or sometimes / yes. one_hand: both / mostly left / mostly right.
  # near_vision: no / a little / yes.
  HAND_QUESTIONS = %i[tremor pinch one_hand fatigue near_vision].freeze
  ANSWERS = 0..2
  RETENTION_DAYS = [ 7, 30 ].freeze

  has_secure_token :token

  # Renders before photos: renders point at photos.
  has_many :renders, dependent: :destroy
  has_many :photos, dependent: :destroy
  has_many :shares, dependent: :delete_all
  # Calls stay for the daily unit count; the database clears their kit_id.
  has_many :provider_calls, dependent: nil

  enum :path, { self_use: 0, helper: 1, example: 2 }, validate: true

  validates(*HAND_QUESTIONS, inclusion: { in: ANSWERS }, allow_nil: true)
  # "My hands today": 0 steady, 1 a bit shaky, 2 very shaky or stiff. Sets target sizes and the repeat-tap guard.
  validates :hands_today, inclusion: { in: ANSWERS }
  validates :retention_days, inclusion: { in: RETENTION_DAYS }

  before_save :schedule_purge

  # The answers as Ease::HandProfile takes them. A question not answered yet counts as the first answer
  # (no / both), which adds no weight.
  def hand_answers
    HAND_QUESTIONS.index_with { |question| public_send(question).to_i }
  end

  def hand_profile
    Ease::HandProfile.new(**hand_answers)
  end

  # Links use the private token: /k/<token>.
  def to_param
    token
  end

  # Called on every visit: retention counts from the last activity.
  def touch_activity!
    update!(last_active_at: Time.current)
  end

  # "Delete everything", and retention: the files go now rather than in a later purge job, then every row.
  # Provider calls stay, without the kit, for the daily unit count.
  def destroy_everything!
    files = photos.includes(image_attachment: :blob).map(&:image) +
      renders.includes(result_attachment: :blob).map(&:result)
    files.each(&:purge)
    destroy!
  end

  private
    def schedule_purge
      self.last_active_at ||= Time.current
      self.purge_after = last_active_at + retention_days.days
    end
end
