# A face photo: today's (what renders go on) or a reference (an old photo wearing a favourite look).
class Photo < ApplicationRecord
  SOURCES = %w[camera upload example].freeze
  # Colours sampled in the browser from face landmarks, as "#RRGGBB".
  SAMPLED_REGIONS = %w[lips lids cheeks skin].freeze

  belongs_to :kit

  enum :kind, { today: 0, reference: 1 }, validate: true

  has_one_attached :image

  validates :source, inclusion: { in: SOURCES }
  validate :sampled_colours_are_hex

  private
    def sampled_colours_are_hex
      return if sampled.is_a?(Hash) &&
        sampled.all? { |region, hex| region.to_s.in?(SAMPLED_REGIONS) && hex.to_s.match?(/\A#\h{6}\z/) }

      errors.add(:sampled, "must map lips, lids, cheeks or skin to a #RRGGBB colour")
    end
end
