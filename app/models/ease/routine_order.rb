module Ease
  # The order to do a routine in.
  #
  # Steps are grouped by face area (face, cheeks, brows, eyes, lips). Areas that hold a precision step go first,
  # the most precise area first, while hands are freshest. The other areas follow in the look's order. Inside an
  # area a step never comes before a lower layer (eyes: lid, then liner, then lashes, so nothing presses on wet
  # mascara); otherwise the look's order is kept. Last comes the finish: the fix-up step (cotton bud and micellar
  # water), then setting spray.
  module RoutineOrder
    # An area with a step at or above this precision goes first.
    PRECISION = 2

    module_function

    def order(steps)
      steps = steps.uniq(&:id)
      finish, rest = steps.partition(&:finish?)
      areas = rest.group_by(&:area).values
      precise, others = areas.partition { |area_steps| precision(area_steps) >= PRECISION }
      precise = precise.each_with_index.sort_by { |area_steps, index| [ -precision(area_steps), index ] }.map(&:first)

      (precise + others).flat_map { |area_steps| by_layer(area_steps) } +
        [ StepCatalogue.fixup ] + finish.reject(&:fixup?)
    end

    def precision(steps)
      steps.map(&:precision).max
    end

    def by_layer(steps)
      steps.each_with_index.sort_by { |step, index| [ step.layer_index, index ] }.map(&:first)
    end
  end
end
