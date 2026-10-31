module Ease
  # One makeup step from config/blendolo/steps.yml.
  #
  #   id            snake_case key, such as "liquid_liner_wing"
  #   number        its row in the ease table (1..29), or nil for an easier step the table names as a swap
  #   name          short name, such as "Winged liquid liner"
  #   layer         where on the face it goes, one of LAYERS, in the order layers go on
  #   instruction   what to do, at most 12 words
  #   dims          { P:, E:, G:, H:, T:, F:, O: }, each 0 (easy) to 3 (hard)
  #   swap          id of the easier step, "skip" to leave the step out, or nil when there is no easier version
  #   swap_why      why the swap is easier, in plain words (nil when there is no swap)
  #   no_swap_why   what to say when the step is hard and stays (see #no_swap_why)
  #   why_easier    why this step is kind to hands, for its step card
  #   tips          technique tips, short sentences
  #   product_type  the kind of product to look for
  #   ease_tags     what makes that product easy to use (see Ease::Words::TAGS)
  #   effect        the effect that renders this step (see docs/effects-vocabulary.md), or nil when it doesn't show
  class Step < Data.define(:id, :number, :name, :layer, :instruction, :dims, :swap, :swap_why, :no_swap_why,
                           :why_easier, :tips, :product_type, :ease_tags, :effect)
    SKIP = "skip".freeze
    FIXUP = "fixup".freeze
    NO_EASIER_SWAP = "No easier swap for your hands.".freeze

    LAYERS = %w[base cheeks brows lid liner lashes lips finish].freeze
    # Layers that share a part of the face. The eyes are done lid, then liner, then lashes.
    AREAS = { "base" => "face", "cheeks" => "cheeks", "brows" => "brows", "lid" => "eyes", "liner" => "eyes",
              "lashes" => "eyes", "lips" => "lips", "finish" => "finish" }.freeze

    def precision = dims.fetch(:P)

    def skip? = swap == SKIP

    def swap_id
      swap unless skip?
    end

    def fixup? = id == FIXUP

    def finish? = layer == "finish"

    def area = AREAS.fetch(layer)

    def layer_index = LAYERS.index(layer)

    # Shown when the planner keeps this step although it isn't easy: the step's own words (mascara's), or
    # "No easier swap for your hands."
    def no_swap_why = super || NO_EASIER_SWAP

    def renders? = !effect.nil?

    def category = effect&.fetch(:category)
  end
end
