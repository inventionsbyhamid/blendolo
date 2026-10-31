# For records that belong to a kit (photos, renders, shares): none can be added to or changed in an example kit,
# which every visitor shares, except while Examples builds it. Deleting is left to the kit (retention).
module ExampleReadOnly
  extend ActiveSupport::Concern

  included do
    validate :kit_is_not_a_read_only_example
  end

  private
    def kit_is_not_a_read_only_example
      errors.add(:base, Kit::EXAMPLE_READ_ONLY) if kit&.read_only_example?
    end
end
