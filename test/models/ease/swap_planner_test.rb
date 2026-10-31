require "test_helper"

class Ease::SwapPlannerTest < ActiveSupport::TestCase
  setup do
    @default = Ease::HandProfile.new
  end

  def test_planner_swaps_wing_for_smudged_pencil
    result = plan(%w[liquid_liner_wing tinted_balm])

    assert_equal %w[smudged_pencil_liner tinted_balm], result[:steps].map(&:id)
    swap = result[:swaps].sole
    assert_equal "liquid_liner_wing", swap[:from].id
    assert_equal "smudged_pencil_liner", swap[:to].id
    assert_match(/no sharp wing/i, swap[:why])
    assert_empty result[:unswappable]
  end

  def test_planner_swaps_wing_for_smudged_pencil_with_a_tremor_too
    result = plan(%w[liquid_liner_wing], Ease::HandProfile.new(tremor: 2))

    assert_equal %w[smudged_pencil_liner], result[:steps].map(&:id)
  end

  def test_mascara_is_unswappable_and_reported
    result = plan(%w[mascara_upper tinted_balm])

    assert_equal %w[mascara_upper tinted_balm], result[:steps].map(&:id)
    assert_empty result[:swaps]
    assert_equal %w[mascara_upper], result[:unswappable].map(&:id)
    assert_match(/no truly easy version/i, result[:unswappable].first.why_easier)
  end

  def test_skip_leaves_the_step_out_and_says_why
    result = plan(%w[liquid_matte_lipstick lip_liner])

    assert_equal %w[tinted_balm], result[:steps].map(&:id)
    skipped = result[:swaps].find { it[:from].id == "lip_liner" }
    assert_nil skipped[:to]
    assert_match(/left out/i, skipped[:why])
  end

  def test_easy_steps_stay_as_they_are
    ids = %w[tinted_moisturiser_fingers bronzer_big_brush one_colour_lid_wash tinted_balm setting_spray]

    result = plan(ids)

    assert_equal ids, result[:steps].map(&:id)
    assert_empty result[:swaps]
    assert_empty result[:unswappable]
  end

  def test_two_steps_swapped_for_the_same_easier_step_appear_once
    result = plan(%w[bullet_lipstick doe_foot_gloss])

    assert_equal %w[tinted_balm], result[:steps].map(&:id)
    assert_equal 2, result[:swaps].size
  end

  def test_swaps_are_one_level_deep
    smudged = Ease::StepCatalogue.fetch("smudged_pencil_liner")

    assert_operator Ease::Scorer.step(smudged, @default), :<, Ease::Words::EASY
    assert_equal %w[smudged_pencil_liner], plan(%w[pencil_liner_crisp])[:steps].map(&:id)
  end

  def test_no_swap_when_the_swap_is_not_easier_for_these_hands
    pinch = Ease::HandProfile.new(pinch: 2)
    stamp = Ease::StepCatalogue.fetch("brow_stamp")
    gel = Ease::StepCatalogue.fetch("tinted_brow_gel")
    assert_operator Ease::Scorer.step(gel, pinch), :<=, Ease::Scorer.step(stamp, pinch), "the gel's twist cap counts"

    result = plan(%w[brow_stamp], pinch)

    assert_equal %w[brow_stamp], result[:steps].map(&:id)
    assert_equal %w[brow_stamp], result[:unswappable].map(&:id)
  end

  def test_every_step_kept_by_some_plan_explains_why_it_is_easier
    answers = [ 0, 1, 2 ]
    kept = answers.product(answers, answers, answers, answers).flat_map do |tremor, pinch, one_hand, fatigue, near_vision|
      profile = Ease::HandProfile.new(tremor:, pinch:, one_hand:, fatigue:, near_vision:)
      Ease::SwapPlanner.new(profile).plan(Ease::StepCatalogue.all)[:steps]
    end

    kept.uniq(&:id).each do |step|
      assert step.why_easier.present?, "#{step.id} can be in an easy routine, so it needs why_easier"
    end
  end

  private
    def plan(ids, profile = @default)
      Ease::SwapPlanner.new(profile).plan(ids.map { Ease::StepCatalogue.fetch(it) })
    end
end
