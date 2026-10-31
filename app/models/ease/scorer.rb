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

    # A look is as easy as its hardest required step. Optional steps (Step#optional?) never set the grade; they come
    # back under optional: with their own ease. Arms that tire lose points for each required step beyond four (the
    # fix-up step doesn't count). The first of equally hard steps is the hardest.
    #
    # -> { ease: 0..100, hardest_step: Step or nil, optional: [{ step:, ease:, words: }] }
    def look(steps, profile)
      required, optional = steps.partition { |step| !step.optional? }
      optional = optional.map do |step|
        ease = step(step, profile)
        { step:, ease:, words: Words.for(ease) }
      end
      return { ease: 100, hardest_step: nil, optional: } if required.empty?

      hardest_step, ease = required.map { |step| [ step, step(step, profile) ] }
        .each_with_index.min_by { |(_step, score), index| [ score, index ] }.first
      counted = required.count { |step| !step.fixup? }
      penalty = profile.fatigue_penalty * [ counted - HandProfile::PENALTY_FREE_STEPS, 0 ].max

      { ease: (ease - penalty).clamp(0, 100), hardest_step:, optional: }
    end
  end
end
