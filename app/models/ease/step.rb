module Ease
  # One makeup step from config/blendolo/steps.yml.
  #
  #   id            snake_case key, such as "liquid_liner_wing"
  #   number        its row in the ease table (1..29), or nil for an easier step the table names as a swap
  #   name          short name, such as "Winged liquid liner"
  #   layer         where on the face it goes, one of LAYERS, in the order layers go on
  #   instruction   what to do, at most 12 words
  #   dims          { P:, E:, G:, H:, T:, F:, O: }, each 0 (easy) to 3 (hard)
  #   swaps         the easier versions, best first when hands differ in nothing: [Candidate(to:, why:)]. to is a step
  #                 id, or "skip" (alone) to leave the step out; empty when there is no easier version. The swap
  #                 planner picks the candidate that is easiest for the person's hands.
  #   no_swap_why   what to say when the step is hard and stays (see #no_swap_why)
  #   why_easier    why this step is kind to hands, for its step card
  #   tips          technique tips, short sentences
  #   product_type  the kind of product to look for
  #   ease_tags     what makes that product easy to use (see Ease::Words::TAGS)
  #   effect        the effect that renders this step (see docs/effects-vocabulary.md), or nil when it doesn't show
  #   optional      true when a look marks the step optional (mascara, lashes, curler, setting spray): it never sets the
  #                 look's grade. Catalogue steps are never optional; Looks::LookStep#step makes the optional copy.
  class Step < Data.define(:id, :number, :name, :layer, :instruction, :dims, :swaps, :no_swap_why, :why_easier,
                           :tips, :product_type, :ease_tags, :effect, :optional)
    # One easier version of a step, and why it is easier, in plain words.
    Candidate = Data.define(:to, :why)

    SKIP = "skip".freeze
    FIXUP = "fixup".freeze
    NO_EASIER_SWAP = "No easier swap for your hands.".freeze
    OPTIONAL_WHY = "Optional. Skip it on shaky days.".freeze

    LAYERS = %w[base cheeks powder brows lid liner lashes lips finish].freeze
    # Layers that share a part of the face. The eyes are done lid, then liner, then lashes.
    AREAS = { "base" => "face", "cheeks" => "cheeks", "powder" => "powder", "brows" => "brows", "lid" => "eyes",
              "liner" => "eyes", "lashes" => "eyes", "lips" => "lips", "finish" => "finish" }.freeze

    def initialize(optional: false, **attributes)
      super
    end

    def precision = dims.fetch(:P)

    def skip? = swaps.size == 1 && swaps.first.to == SKIP

    # The first candidate: what the table names first. The planner may pick another one for a person's hands.
    def swap = swaps.first&.to

    def swap_why = swaps.first&.why

    def swap_id
      swap unless skip?
    end

    # Ids of the easier steps this step can become (none for a skip).
    def swap_ids = skip? ? [] : swaps.map(&:to)

    def fixup? = id == FIXUP

    def finish? = layer == "finish"

    def area = AREAS.fetch(layer)

    def layer_index = LAYERS.index(layer)

    def optional? = optional

    # This step as a look's optional step.
    def as_optional = optional? ? self : with(optional: true)

    # Shown on an optional step: "Optional. Skip it on shaky days."
    def optional_why = (OPTIONAL_WHY if optional?)

    # Shown when the planner keeps this step although it isn't easy: the step's own words (mascara's), or
    # "No easier swap for your hands."
    def no_swap_why = super || NO_EASIER_SWAP

    def renders? = !effect.nil?

    def category = effect&.fetch(:category)
  end
end
