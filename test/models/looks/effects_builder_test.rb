require "test_helper"

class Looks::EffectsBuilderTest < ActiveSupport::TestCase
  setup do
    @default = Ease::HandProfile.new
    @red_lip = Looks::Catalogue.fetch(:red_lip)
  end

  def test_red_lip_classic_has_matte_lip_and_liner
    effects = by_category(Looks::EffectsBuilder.build(@red_lip.steps))

    assert_equal "matte", effects["lip_color"][:texture]
    assert_equal "#B0182A", effects["lip_color"][:colour]
    assert_equal 85, effects["lip_color"][:intensity]
    assert_equal "Natural1", effects["lip_liner"][:pattern]
    assert_equal "#8E1424", effects["lip_liner"][:colour]
  end

  def test_easy_red_lip_is_sheer_without_liner
    effects = by_category(Looks::EffectsBuilder.build(@red_lip.easy_steps(@default)))

    lip = effects.fetch("lip_color")
    assert_equal "sheer", lip[:texture]
    assert_equal "#B0182A", lip[:colour], "the easy lip keeps the look's red"
    assert_equal 45, lip[:intensity]
    assert_equal 35, lip[:gloss]
    assert_equal 60, lip[:transparency]
    assert_not effects.key?("lip_liner")
  end

  def test_winged_look_easy_uses_smoke_pattern_at_88
    classic = by_category(Looks::EffectsBuilder.build(@red_lip.steps))
    easy = by_category(Looks::EffectsBuilder.build(@red_lip.easy_steps(@default)))

    assert_equal "OpenWings2", classic["eye_liner"][:pattern]
    assert_match(/\ASmoke\d+\z/, easy["eye_liner"][:pattern])
    assert_equal 88, easy["eye_liner"][:intensity]
    assert_equal "#2B1D16", easy["eye_liner"][:colour], "a near black brown for a soft line"
  end

  def test_other_swaps_follow_the_swap_parameters
    wedding = Looks::Catalogue.fetch(:wedding_guest)
    classic = by_category(Looks::EffectsBuilder.build(wedding.steps, skin: "#C08A6A"))
    easy = by_category(Looks::EffectsBuilder.build(wedding.easy_steps(@default), skin: "#C08A6A"))

    assert_equal "UpperDense1", classic["eyelashes"][:pattern]
    assert_equal [ "Natural2", 75 ], easy["eyelashes"].values_at(:pattern, :intensity), "strip lashes become mascara"
    assert_equal "shape", classic["eyebrows"][:mode]
    assert_equal [ "color", nil ], easy["eyebrows"].values_at(:mode, :pattern), "drawn brows become a tint"
    assert_equal 3, classic["eye_shadow"][:colour].size
    assert_kind_of String, easy["eye_shadow"][:colour], "a cut crease becomes one colour"
    assert_equal "#B8924A", easy["eye_shadow"][:colour], "the main shade is kept"
    assert classic.key?("contour")
    assert_not easy.key?("contour")
    assert_equal "bronzer", easy.fetch("bronzer")[:category]
    assert_equal [ 60, 25 ], [ classic["foundation"][:coverage], easy["foundation"][:coverage] ]
    assert_equal [ "matte", "satin", 30 ], [ classic["blush"][:texture], *easy["blush"].values_at(:texture, :glow) ]
  end

  def test_skin_colour_fills_foundation_and_concealer
    effects = by_category(Looks::EffectsBuilder.build(%w[liquid_foundation_brush concealer_wand], skin: "#c08a6a"))

    assert_equal "#C08A6A", effects["foundation"][:colour]
    assert_equal "#C08A6A", effects["concealer"][:colour]
  end

  def test_base_steps_are_left_out_without_a_skin_colour
    effects = Looks::EffectsBuilder.build(%w[liquid_foundation_brush tinted_balm])

    assert_equal %w[lip_color], effects.map { it[:category] }
  end

  def test_steps_that_do_not_show_are_left_out
    assert_empty Looks::EffectsBuilder.build(%w[pressed_powder_compact setting_spray fixup])
  end

  def test_one_effect_per_category_and_the_first_wins
    effects = Looks::EffectsBuilder.build(%w[liquid_matte_lipstick doe_foot_gloss])

    assert_equal [ [ "lip_color", "matte" ] ], effects.map { it.values_at(:category, :texture) }
  end

  def test_effects_have_the_core_keys_in_order_then_settings
    effect = Looks::EffectsBuilder.build([ { "step" => "tinted_balm", "colour" => "#b85c6b" } ]).sole

    assert_equal({ category: "lip_color", colour: "#B85C6B", intensity: 45, texture: "sheer", pattern: "original",
                   mode: "full", gloss: 35, transparency: 60 }, effect)
    assert_equal %i[category colour intensity texture pattern mode gloss transparency], effect.keys
  end

  def test_colours_fit_the_pattern
    assert_equal "#111111", Looks::EffectsBuilder.fit_colour([ "#111111", "#222222" ], "#000000")
    assert_equal [ "#AAAAAA", "#AAAAAA" ], Looks::EffectsBuilder.fit_colour("#aaaaaa", [ "#000000", "#111111" ])
    assert_equal [ "#AAAAAA", "#BBBBBB", "#BBBBBB" ],
                 Looks::EffectsBuilder.fit_colour([ "#AAAAAA", "#BBBBBB" ], [ "#0", "#1", "#2" ])
  end

  def test_every_step_effect_is_valid_in_our_vocabulary
    Ease::StepCatalogue.all.select(&:renders?).each do |step|
      effect = Looks::EffectsBuilder.effect_for(Looks::LookStep.new(step_id: step.id), skin: "#C08A6A")

      assert_empty Looks::Vocabulary.errors(effect), step.id
    end
  end

  def test_every_look_builds_valid_effects_classic_and_easy
    profiles = [ @default, Ease::HandProfile.new(tremor: 2, pinch: 2, one_hand: 1, fatigue: 2, near_vision: 2) ]

    Looks::Catalogue.all.each do |look|
      sets = [ look.steps ] + profiles.map { look.easy_steps(it) }
      sets.each do |steps|
        Looks::EffectsBuilder.build(steps, skin: "#7E4A30").each do |effect|
          assert_empty Looks::Vocabulary.errors(effect), "#{look.key}: #{effect}"
        end
      end
    end
  end

  def test_built_effects_are_independent_of_the_catalogue
    effect = Looks::EffectsBuilder.build(%w[brow_pencil]).sole

    effect[:shape][:thickness] += 10

    assert_equal 10, Ease::StepCatalogue.fetch("brow_pencil").effect[:shape][:thickness]
    assert_equal 10, Looks::EffectsBuilder.build(%w[brow_pencil]).sole[:shape][:thickness]
  end

  def test_stored_routine_reads_back_the_same
    steps = @red_lip.easy_steps(@default)
    stored = JSON.parse(steps.map(&:to_h).to_json)

    assert_equal steps, stored.map { Looks::LookStep.wrap(it) }
  end

  def test_signature_from_samples_and_answers
    sampled = { "lips" => "#9A2A35", "lids" => "#7A5444", "cheeks" => "#D08C78", "skin" => "#C08A6A" }

    steps = Looks::EffectsBuilder.signature(sampled:, liner: "winged", lips: "matte")

    assert_equal [ [ "powder_blush_brush", "#E07B62" ], [ "one_colour_lid_wash", "#6B4632" ],
                   [ "liquid_liner_wing", nil ], [ "liquid_matte_lipstick", "#8E1F2F" ] ],
                 steps.map { [ it.step_id, it.colour ] }

    effects = by_category(Looks::EffectsBuilder.build(steps))
    assert_equal [ "matte", "#8E1F2F" ], effects["lip_color"].values_at(:texture, :colour)
    assert_equal "OpenWings2", effects["eye_liner"][:pattern]

    easy = by_category(Looks::EffectsBuilder.build(Looks::Look.easy_steps(steps, @default)))
    assert_equal [ "sheer", "#8E1F2F" ], easy["lip_color"].values_at(:texture, :colour)
    assert_equal [ "Smoke19", 88 ], easy["eye_liner"].values_at(:pattern, :intensity), "shadow liner for the default hands"
  end

  def test_signature_answers_choose_the_steps
    sampled = { lips: "#C9787A" }

    assert_equal %w[smudged_pencil_liner doe_foot_gloss],
                 Looks::EffectsBuilder.signature(sampled:, liner: :smudged, lips: :shiny).map(&:step_id)
    assert_equal %w[liquid_liner_thin tinted_balm],
                 Looks::EffectsBuilder.signature(sampled:, liner: "thin", lips: "sheer").map(&:step_id)
    assert_equal %w[tinted_balm], Looks::EffectsBuilder.signature(sampled:, liner: "none", lips: "sheer").map(&:step_id)
    assert_empty Looks::EffectsBuilder.signature(sampled: {}, liner: "none", lips: "matte"), "nothing sampled, nothing guessed"
    assert_raises(ArgumentError) { Looks::EffectsBuilder.signature(sampled:, liner: "cat eye", lips: "matte") }
    assert_raises(ArgumentError) { Looks::EffectsBuilder.signature(sampled:, liner: "none", lips: "glitter") }
  end

  private
    def by_category(effects) = effects.index_by { it[:category] }
end
