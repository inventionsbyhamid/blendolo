module Ease
  # How easy a step or a look is for one pair of hands, 0 (very hard) to 100 (very easy).
  module Scorer
    MAX_PER_DIMENSION = 3

    module_function

    # round(100 x (1 - weighted sum / weighted max)), worked in exact fractions so .5 always rounds up.
    def step(step, profile)
      weights = profile.weights.transform_values(&:to_r)
      sum = HandProfile::DIMENSIONS.sum { |dimension| weights[dimension] * step.dims.fetch(dimension) }
      max = HandProfile::DIMENSIONS.sum { |dimension| weights[dimension] * MAX_PER_DIMENSION }

      (100 * (1 - sum / max)).round
    end

    # A look is as easy as its hardest step. Arms that tire lose points for each step beyond four
    # (the fix-up step doesn't count). The first of equally hard steps is the hardest.
    def look(steps, profile)
      return { ease: 100, hardest_step: nil } if steps.empty?

      hardest_step, ease = steps.map { |step| [ step, step(step, profile) ] }
        .each_with_index.min_by { |(_step, score), index| [ score, index ] }.first
      counted = steps.count { |step| !step.fixup? }
      penalty = profile.fatigue_penalty * [ counted - HandProfile::PENALTY_FREE_STEPS, 0 ].max

      { ease: (ease - penalty).clamp(0, 100), hardest_step: }
    end
  end
end
