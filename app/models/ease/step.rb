module Ease
  # One makeup step from config/blendolo/steps.yml.
  #
  #   id            snake_case key, such as "liquid_liner_wing"
  #   number        its row in the ease table (1..29), or nil for an easier step the table names as a swap
  #   name          short name, such as "Winged liquid liner"
  #   instruction   what to do, at most 12 words
  #   dims          { P:, E:, G:, H:, T:, F:, O: }, each 0 (easy) to 3 (hard)
  #   swap          id of the easier step, "skip" to leave the step out, or nil when there is no easier version
  #   swap_why      why the swap is easier, in plain words (nil when there is no swap)
  #   why_easier    why this step is kind to hands, for its step card
  #   tips          technique tips, short sentences
  #   product_type  the kind of product to look for
  #   ease_tags     what makes that product easy to use (see Ease::Words::TAGS)
  #   effect        the effect that renders this step (see docs/effects-vocabulary.md), or nil when it doesn't show
  class Step < Data.define(:id, :number, :name, :instruction, :dims, :swap, :swap_why, :why_easier,
                           :tips, :product_type, :ease_tags, :effect)
    SKIP = "skip".freeze
    FIXUP = "fixup".freeze

    def precision = dims.fetch(:P)

    def skip? = swap == SKIP

    def swap_id
      swap unless skip?
    end

    def fixup? = id == FIXUP

    def renders? = !effect.nil?

    def category = effect&.fetch(:category)
  end
end
