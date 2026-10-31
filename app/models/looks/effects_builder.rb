module Looks
  # Turns look steps into effects in our own vocabulary (Looks::Vocabulary, docs/effects-vocabulary.md), ready for
  # the appearance provider.
  module EffectsBuilder
    # Signature look answers: "Did you wear eyeliner?" and "Lips?"
    LINER_STEPS = { "winged" => "liquid_liner_wing", "thin" => "liquid_liner_thin",
                    "smudged" => "smudged_pencil_liner", "none" => nil }.freeze
    LIP_STEPS = { "matte" => "liquid_matte_lipstick", "shiny" => "doe_foot_gloss", "sheer" => "tinted_balm" }.freeze

    module_function

    # steps: look steps (or anything Looks::LookStep.wrap reads). skin: "#RRGGBB" for foundation and concealer.
    #
    # Steps that don't show in a preview are left out. Foundation and concealer are left out unless the look gives
    # a colour or the skin colour is known: we never guess someone's skin shade. One effect per category; when two
    # steps share one, the first wins.
    def build(steps, skin: nil)
      steps.map { |step| LookStep.wrap(step) }
        .filter_map { |look_step| effect_for(look_step, skin: skin&.upcase) }
        .uniq { |effect| effect[:category] }
    end

    # The classic steps of a signature look, from colours sampled on the old photo ({ lips:, lids:, cheeks:, skin: },
    # string or symbol keys, any of them missing) and the two answers (liner: winged, thin, smudged or none;
    # lips: matte, shiny or sheer). Sampled colours snap to the nearest shade we render well. A region that
    # wasn't sampled is left out rather than guessed.
    def signature(sampled:, liner:, lips:)
      colours = ColourSamplerMapping.map(sampled)
      liner_step = LINER_STEPS.fetch(liner.to_s) { raise ArgumentError, "Unknown liner answer #{liner.inspect}" }
      lip_step = LIP_STEPS.fetch(lips.to_s) { raise ArgumentError, "Unknown lips answer #{lips.inspect}" }

      [
        ([ "powder_blush_brush", colours[:cheeks] ] if colours[:cheeks]),
        ([ "one_colour_lid_wash", colours[:lids] ] if colours[:lids]),
        ([ liner_step, nil ] if liner_step),
        ([ lip_step, colours[:lips] ] if colours[:lips])
      ].compact.map { |step_id, colour| LookStep.new(step_id:, colour:) }
    end

    def effect_for(look_step, skin: nil)
      fragment = look_step.step.effect
      return unless fragment

      colour = look_step.colour || (skin if Vocabulary::BASE.include?(fragment[:category])) || fragment[:colour]
      return unless colour

      {
        category: fragment.fetch(:category),
        colour: fit_colour(colour, fragment[:colour]),
        intensity: look_step.intensity || fragment.fetch(:intensity),
        texture: fragment[:texture],
        pattern: fragment[:pattern],
        mode: fragment[:mode]
      }.merge(fragment.slice(*Vocabulary::OPTIONAL_KEYS).deep_dup)
    end

    # A pattern takes as many colours as its default has. Extra colours drop off the end; missing ones repeat
    # the last given. So a three-colour crease swapped for a one-colour wash keeps its first (main) shade.
    def fit_colour(colour, default)
      count = default.is_a?(Array) ? default.size : 1
      list = Array(colour).map(&:upcase).first(count)
      list += [ list.last ] * (count - list.size)

      default.is_a?(Array) ? list : list.first
    end
  end
end
