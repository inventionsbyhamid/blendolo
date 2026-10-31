module Ease
  # The order to do a routine in: precision steps first while hands are freshest (most precise first), then the
  # rest in the look's order, then the fix-up step (cotton bud and micellar water) last.
  module RoutineOrder
    # Steps with precision at or above this go first.
    PRECISION = 2

    module_function

    def order(steps)
      steps = steps.reject(&:fixup?).uniq(&:id)
      precise, rest = steps.partition { |step| step.precision >= PRECISION }
      precise = precise.each_with_index.sort_by { |step, index| [ -step.precision, index ] }.map(&:first)

      precise + rest + [ StepCatalogue.fixup ]
    end
  end
end
