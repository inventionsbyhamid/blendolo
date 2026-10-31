module Ease
  # Swaps the steps that aren't easy for these hands for their easier version.
  #
  # A step below Easy (80) is swapped when its swap scores higher for this profile, or left out when its swap is
  # "skip". Swaps go one level deep: the easier step is never swapped again. A step below Easy with nothing easier
  # stays and is reported as unswappable (mascara is the usual one), so the app can say so and offer tips: each
  # unswappable step's #no_swap_why is the line to show ("No easier swap for your hands." unless the step has
  # its own, as mascara does).
  class SwapPlanner
    def initialize(profile)
      @profile = profile
    end

    # -> { steps: [Step], swaps: [{ from: Step, to: Step or nil (left out), why: String }], unswappable: [Step] }
    def plan(steps)
      planned = []
      swaps = []
      unswappable = []

      steps.each do |step|
        ease = Scorer.step(step, @profile)

        if ease >= Words::EASY
          planned << step
        elsif step.skip?
          swaps << { from: step, to: nil, why: step.swap_why }
        elsif (easier = easier_than(step, ease))
          planned << easier
          swaps << { from: step, to: easier, why: step.swap_why }
        else
          planned << step
          unswappable << step
        end
      end

      { steps: planned.uniq(&:id), swaps:, unswappable: }
    end

    private
      def easier_than(step, ease)
        return unless step.swap_id

        swap = StepCatalogue.fetch(step.swap_id)
        swap if Scorer.step(swap, @profile) > ease
      end
  end
end
