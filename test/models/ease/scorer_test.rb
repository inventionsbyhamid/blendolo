require "test_helper"

class Ease::ScorerTest < ActiveSupport::TestCase
  # The "Ease" column of the ease table, step by step, with equal weights.
  RESEARCH_TABLE = {
    "liquid_foundation_brush" => 78, "concealer_wand" => 72, "pressed_powder_compact" => 72,
    "powder_blush_brush" => 67, "bronzer_big_brush" => 83, "contour_line" => 61, "highlighter_fan_brush" => 72,
    "brow_pencil" => 39, "brow_powder_brush" => 50, "brow_stamp" => 78, "one_colour_lid_wash" => 89,
    "two_tone_crease" => 56, "cut_crease" => 28, "pencil_liner_crisp" => 50, "gel_liner_brush" => 28,
    "liquid_liner_thin" => 33, "liquid_liner_wing" => 28, "tightline" => 28, "mascara_upper" => 44,
    "mascara_lower" => 33, "eyelash_curler" => 39, "strip_lashes" => 0, "magnetic_liner_lashes" => 28,
    "bullet_lipstick" => 72, "liquid_matte_lipstick" => 44, "lip_liner" => 44, "tinted_balm" => 94,
    "doe_foot_gloss" => 72, "setting_spray" => 89
  }.freeze

  # The ease the table gives each easier swap it names, and the fix-up step.
  SWAP_TABLE = {
    "tinted_moisturiser_fingers" => 94, "stick_concealer_finger" => 83, "kabuki_powder" => 89,
    "cream_blush_fingers" => 89, "bronzer_stick_sponge" => 89, "cream_highlighter_finger" => 89,
    "tinted_brow_gel" => 83, "wash_and_smudged_lash_line" => 72, "smudged_pencil_liner" => 67,
    "shadow_liner" => 72, "fixup" => 94
  }.freeze

  setup do
    @default = Ease::HandProfile.new
  end

  def test_default_weights_reproduce_research_table
    assert_equal 28, ease("liquid_liner_wing")
    assert_equal 94, ease("tinted_balm")
    assert_equal 39, ease("brow_pencil")
    assert_equal 72, ease("bullet_lipstick")

    RESEARCH_TABLE.merge(SWAP_TABLE).each do |id, expected|
      assert_equal expected, ease(id), "ease of #{id}"
    end
  end

  def test_tremor_lowers_precision_steps
    tremor = Ease::HandProfile.new(tremor: 2)

    assert_operator ease("liquid_liner_wing", tremor), :<, 28
    assert_operator ease("lip_liner", tremor), :<, ease("lip_liner")
    assert_equal 87, ease("liquid_foundation_brush", tremor), "steps that need no precision rise in comparison"
  end

  def test_scores_stay_within_0_to_100_for_every_step_and_profile
    every_profile.each do |profile|
      Ease::StepCatalogue.all.each do |step|
        assert_includes 0..100, Ease::Scorer.step(step, profile)
      end
    end
  end

  def test_look_ease_is_hardest_step
    result = Ease::Scorer.look(steps(%w[tinted_balm liquid_liner_wing cream_blush_fingers]), @default)

    assert_equal 28, result[:ease]
    assert_equal "liquid_liner_wing", result[:hardest_step].id
  end

  def test_first_of_equally_hard_steps_is_the_hardest
    assert_equal "cut_crease", Ease::Scorer.look(steps(%w[cut_crease liquid_liner_wing]), @default)[:hardest_step].id
  end

  def test_empty_look_is_easy
    assert_equal({ ease: 100, hardest_step: nil }, Ease::Scorer.look([], @default))
  end

  def test_fatigue_penalises_long_routines
    six_steps = steps(%w[tinted_moisturiser_fingers cream_blush_fingers tinted_brow_gel one_colour_lid_wash
                         tinted_balm setting_spray])
    tired = Ease::HandProfile.new(fatigue: 2)
    sometimes = Ease::HandProfile.new(fatigue: 1)

    assert_equal 83, Ease::Scorer.look(six_steps, @default)[:ease], "no penalty without fatigue"
    assert_equal hardest(six_steps, tired) - 4 * 2, Ease::Scorer.look(six_steps, tired)[:ease]
    assert_equal hardest(six_steps, sometimes) - 2 * 2, Ease::Scorer.look(six_steps, sometimes)[:ease]
    assert_equal hardest(six_steps.first(4), tired), Ease::Scorer.look(six_steps.first(4), tired)[:ease]
  end

  def test_fixup_step_does_not_count_towards_fatigue_penalty
    tired = Ease::HandProfile.new(fatigue: 2)
    four_steps = steps(%w[tinted_moisturiser_fingers cream_blush_fingers tinted_brow_gel tinted_balm])

    assert_equal Ease::Scorer.look(four_steps, tired)[:ease], Ease::Scorer.look(four_steps + steps(%w[fixup]), tired)[:ease]
  end

  def test_long_look_for_tired_arms_never_goes_below_0
    assert_equal 0, Ease::Scorer.look(Ease::StepCatalogue.all.first(20), Ease::HandProfile.new(fatigue: 2))[:ease]
  end

  private
    def steps(ids) = ids.map { Ease::StepCatalogue.fetch(it) }

    def ease(id, profile = @default) = Ease::Scorer.step(Ease::StepCatalogue.fetch(id), profile)

    def hardest(steps, profile) = steps.map { Ease::Scorer.step(it, profile) }.min

    def every_profile
      answers = [ 0, 1, 2 ]
      answers.product(answers, answers, answers, answers).map do |tremor, pinch, one_hand, fatigue, near_vision|
        Ease::HandProfile.new(tremor:, pinch:, one_hand:, fatigue:, near_vision:)
      end
    end
end
