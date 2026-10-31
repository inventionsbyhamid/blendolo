module Ease
  # Swaps the steps that aren't easy for these hands for their easier version.
  #
  # A step below Easy (80) is swapped for the candidate that scores highest for this profile (the first listed wins a
  # tie), when that beats the step, or left out when its swap is "skip". Swaps go one level deep: the easier step is
  # never swapped again. A step below Easy with nothing easier stays and is reported as unswappable (mascara is the
  # usual one), so the app can say so and offer tips: each unswappable step's #no_swap_why is the line to show
  # ("No easier swap for your hands." unless the step has its own, as mascara does).
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
        elsif (candidate, easier = easiest_swap(step, ease))
          planned << easier
          swaps << { from: step, to: easier, why: candidate.why }
        else
          planned << step
          unswappable << step
        end
      end

      { steps: planned.uniq(&:id), swaps:, unswappable: }
    end

    private
      # [candidate, its step] for the candidate easiest for these hands, when it beats the step; nil otherwise.
      def easiest_swap(step, ease)
        scored = step.swap_ids.each_with_index.map do |id, index|
          easier = StepCatalogue.fetch(id)
          [ step.swaps[index], easier, Scorer.step(easier, @profile), index ]
        end
        candidate, easier, score, _index = scored.max_by { |_candidate, _easier, score, index| [ score, -index ] }

        [ candidate, easier ] if candidate && score > ease
      end
  end
end
