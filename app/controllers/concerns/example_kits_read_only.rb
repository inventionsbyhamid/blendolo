# Example people's kits are shared by every visitor, so nothing a visitor taps changes them. Actions that would
# write say so and point to starting your own kit. ("My hands today" still works: it is kept per visitor.) The models
# refuse such writes too (Kit::EXAMPLE_READ_ONLY); a refusal that gets that far ends the same way.
module ExampleKitsReadOnly
  extend ActiveSupport::Concern

  included do
    rescue_from Kit::ReadOnlyExample, with: :example_kit_unchanged
    rescue_from ActiveRecord::RecordInvalid do |error|
      raise error unless error.record.errors[:base].include?(Kit::EXAMPLE_READ_ONLY)

      example_kit_unchanged
    end
  end

  private
    def keep_example_kits_as_they_are
      example_kit_unchanged if @kit&.example?
    end

    def example_kit_unchanged
      name = Examples.fetch(@kit.example_key).name
      redirect_to url_from(request.referer) || kit_path(@kit),
        notice: "This is #{name}'s example kit, so it stays as it is. Start your own kit to make it yours."
    end
end
