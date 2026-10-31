module Ease
  # The five "Your hands" answers, turned into a weight for each ease dimension.
  #
  # Every answer is 0..2:
  #   tremor       0 no, 1 a little, 2 a lot
  #   pinch        0 no, 1 sometimes, 2 yes (pinching or gripping small things is hard or sore)
  #   one_hand     0 both, 1 mostly left, 2 mostly right
  #   fatigue      0 no, 1 sometimes, 2 yes (arms tire quickly)
  #   near_vision  0 no, 1 a little, 2 yes (close-up reading is hard)
  #
  # Dimensions: P precision, E near the eye, G grip, H hands needed, T time and strokes, F forgiveness,
  # O opening the product. P to F weigh 1 by default; O weighs 0 until pinch or one hand makes it count.
  class HandProfile < Data.define(:tremor, :pinch, :one_hand, :fatigue, :near_vision)
    DIMENSIONS = %i[P E G H T F O].freeze
    DEFAULT_WEIGHTS = { P: 1, E: 1, G: 1, H: 1, T: 1, F: 1, O: 0 }.freeze
    ANSWERS = 0..2

    # Weights each answer asks for. "A little" or "sometimes" adds half the extra over the default.
    RAISES = {
      tremor: { 1 => { P: 2, E: 1.5, F: 1.5 }, 2 => { P: 3, E: 2, F: 2 } },
      pinch: { 1 => { G: 2, O: 1.5, H: 1.25, T: 1.25 }, 2 => { G: 3, O: 3, H: 1.5, T: 1.5 } },
      one_hand: { 1 => { H: 3, O: 3, G: 1.5 }, 2 => { H: 3, O: 3, G: 1.5 } },
      fatigue: { 1 => { T: 2 }, 2 => { T: 3 } },
      near_vision: { 1 => { P: 1.5, E: 1.5 }, 2 => { P: 2, E: 2 } }
    }.freeze

    # Points taken off a look's ease for each step beyond four, by the fatigue answer.
    FATIGUE_PENALTY = { 0 => 0, 1 => 2, 2 => 4 }.freeze
    PENALTY_FREE_STEPS = 4

    def initialize(tremor: 0, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
      answers = { tremor:, pinch:, one_hand:, fatigue:, near_vision: }
      super(**answers.to_h { |question, answer| [ question, self.class.answer(question, answer) ] })
    end

    def self.answer(question, value)
      number = Integer(value, exception: false) if value.is_a?(Integer) || value.is_a?(String)
      return number if ANSWERS.cover?(number)

      raise ArgumentError, "#{question} must be 0, 1 or 2, got #{value.inspect}"
    end

    # { P:, E:, G:, H:, T:, F:, O: }. When two answers raise the same weight, the larger one wins.
    def weights
      to_h.each_with_object(DEFAULT_WEIGHTS.dup) do |(question, answer), weights|
        RAISES.fetch(question).fetch(answer, {}).each do |dimension, weight|
          weights[dimension] = [ weights[dimension], weight ].max
        end
      end
    end

    # Points off a look's ease for each step beyond four.
    def fatigue_penalty
      FATIGUE_PENALTY.fetch(fatigue)
    end

    def default?
      to_h.values.all?(&:zero?)
    end
  end
end
