module Looks
  # A look from config/blendolo/looks.yml: its classic steps, with colours, in the order you'd do them.
  class Look < Data.define(:key, :name, :blurb, :steps, :thumbnail)
    # Swaps for these hands: { steps:, swaps:, unswappable: } (see Ease::SwapPlanner). Works for any look steps,
    # such as a signature look's.
    def self.plan(look_steps, profile)
      Ease::SwapPlanner.new(profile).plan(look_steps.map { |step| LookStep.wrap(step).step })
    end

    # The easy version as look steps. A swapped step keeps the look's colour, stays optional when it was, and takes the
    # easier step's own intensity (that is part of the swap: a smudged line needs a stronger colour, a sheer balm a
    # lighter one). Skipped steps drop out.
    def self.easy_steps(look_steps, profile)
      look_steps = look_steps.map { |step| LookStep.wrap(step) }
      swaps = plan(look_steps, profile)[:swaps].index_by { |swap| swap[:from].id }

      look_steps.filter_map do |look_step|
        swap = swaps[look_step.step_id]
        next look_step unless swap
        next unless swap[:to]

        LookStep.new(step_id: swap[:to].id, colour: look_step.colour, optional: look_step.optional)
      end.uniq(&:step_id)
    end

    # The classic steps as ease steps, for scoring.
    def ease_steps
      steps.map(&:step)
    end

    def plan(profile)
      self.class.plan(steps, profile)
    end

    def easy_steps(profile)
      self.class.easy_steps(steps, profile)
    end
  end
end
