# A face photo: today's (what renders go on) or a reference (an old photo wearing a favourite look).
class Photo < ApplicationRecord
  SOURCES = %w[camera upload example].freeze
  # Colours sampled in the browser from face landmarks, as "#RRGGBB".
  SAMPLED_REGIONS = %w[lips lids cheeks skin].freeze

  belongs_to :kit
  has_many :renders, dependent: :destroy
  has_many :renders_as_reference, class_name: "Render", foreign_key: :reference_photo_id,
    inverse_of: :reference_photo, dependent: :destroy

  enum :kind, { today: 0, reference: 1 }, validate: true

  has_one_attached :image

  validates :source, inclusion: { in: SOURCES }
  validate :sampled_colours_are_hex

  # SHA-256 of the image bytes: the provider cache key. Computed once if the upload didn't set it.
  def content_sha256!
    sha256.presence || Digest::SHA256.hexdigest(image.download).tap { |digest| update_column(:sha256, digest) }
  end

  def to_appearance_image
    Appearance::Image.new(io: StringIO.new(image.download), filename: image.filename.to_s, content_type: image.content_type)
  end

  private
    def sampled_colours_are_hex
      return if sampled.is_a?(Hash) &&
        sampled.all? { |region, hex| region.to_s.in?(SAMPLED_REGIONS) && hex.to_s.match?(/\A#\h{6}\z/) }

      errors.add(:sampled, "must map lips, lids, cheeks or skin to a #RRGGBB colour")
    end
end
