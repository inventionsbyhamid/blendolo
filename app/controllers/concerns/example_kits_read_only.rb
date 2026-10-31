# Example people's kits are shared by every visitor, so nothing a visitor taps changes them. Actions that would
# write say so and point to starting your own kit. ("My hands today" still works: it is kept per visitor.)
module ExampleKitsReadOnly
  extend ActiveSupport::Concern

  private
    def keep_example_kits_as_they_are
      return unless @kit&.example?

      name = Examples.fetch(@kit.example_key).name
      redirect_to url_from(request.referer) || kit_path(@kit),
        notice: "This is #{name}'s example kit, so it stays as it is. Start your own kit to make it yours."
    end
end
