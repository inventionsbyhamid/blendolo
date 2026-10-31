require "test_helper"

class Ease::SwapPlannerTest < ActiveSupport::TestCase
  setup do
    @default = Ease::HandProfile.new
  end

  def test_planner_swaps_wing_for_smudged_pencil
    # Sore pinch: the pencil's cap pulls straight off, while a shadow pan needs a small brush and a lid to open.
    result = plan(%w[liquid_liner_wing tinted_balm], Ease::HandProfile.new(pinch: 2))

    assert_equal %w[smudged_pencil_liner tinted_balm], result[:steps].map(&:id)
    swap = result[:swaps].sole
    assert_equal "liquid_liner_wing", swap[:from].id
    assert_equal "smudged_pencil_liner", swap[:to].id
    assert_match(/short dabs/i, swap[:why], "the why belongs to the chosen candidate")
    assert_empty result[:unswappable]
  end

  def test_planner_picks_easiest_candidate_for_profile
    tremor = Ease::HandProfile.new(tremor: 2)
    wing = Ease::StepCatalogue.fetch("liquid_liner_wing")
    shadow, pencil = %w[shadow_liner smudged_pencil_liner].map { Ease::StepCatalogue.fetch(it) }
    assert_equal %w[shadow_liner smudged_pencil_liner], wing.swap_ids
    assert_operator Ease::Scorer.step(shadow, tremor), :>, Ease::Scorer.step(pencil, tremor)

    swap = plan(%w[liquid_liner_wing], tremor)[:swaps].sole

    assert_equal "shadow_liner", swap[:to].id, "a tremor a lot: pressing shadow needs less precision than a pencil"
    assert_match(/dark shadow pressed/i, swap[:why])
    assert_equal "smudged_pencil_liner", plan(%w[liquid_liner_wing], Ease::HandProfile.new(one_hand: 1))[:swaps].sole[:to].id
  end

  def test_a_tie_between_candidates_goes_to_the_first_listed
    concealer, gel = %w[stick_concealer_finger tinted_brow_gel].map { Ease::StepCatalogue.fetch(it) }
    assert_equal Ease::Scorer.step(concealer, @default), Ease::Scorer.step(gel, @default)
    hard = gel.with(id: "hard_step", dims: { P: 3, E: 3, G: 3, H: 3, T: 3, F: 3, O: 3 })

    [ %w[stick_concealer_finger tinted_brow_gel], %w[tinted_brow_gel stick_concealer_finger] ].each do |ids|
      step = hard.with(swaps: ids.map { Ease::Step::Candidate.new(to: it, why: it) })

      assert_equal ids.first, Ease::SwapPlanner.new(@default).plan([ step ])[:swaps].sole[:to].id
    end
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

  def test_brow_stamp_has_no_invented_swap_and_is_reported_unswappable
    [ @default, Ease::HandProfile.new(pinch: 2) ].each do |profile|
      result = plan(%w[brow_stamp], profile)

      assert_equal %w[brow_stamp], result[:steps].map(&:id)
      assert_empty result[:swaps]
      assert_equal %w[brow_stamp], result[:unswappable].map(&:id)
      assert_equal "No easier swap for your hands.", result[:unswappable].sole.no_swap_why
    end
  end

  def test_mascara_keeps_its_own_words_when_unswappable
    assert_equal "There is no truly easy version of mascara.", plan(%w[mascara_upper])[:unswappable].sole.no_swap_why
  end

  def test_no_swap_when_the_swap_is_not_easier_for_these_hands
    gel = Ease::StepCatalogue.fetch("tinted_brow_gel")
    # A made-up step whose swap is the gel. With pinch pain the gel's twist cap makes the gel no easier.
    stamp_like = gel.with(id: "stamp_like", dims: { P: 1, E: 1, G: 1, H: 0, T: 0, F: 1, O: 1 },
                          swaps: [ Ease::Step::Candidate.new(to: gel.id, why: "gel") ])
    pinch = Ease::HandProfile.new(pinch: 2)
    assert_operator Ease::Scorer.step(stamp_like, pinch), :<, Ease::Words::EASY
    assert_operator Ease::Scorer.step(gel, pinch), :<=, Ease::Scorer.step(stamp_like, pinch), "the gel's twist cap counts"

    result = Ease::SwapPlanner.new(pinch).plan([ stamp_like ])

    assert_equal %w[stamp_like], result[:steps].map(&:id)
    assert_equal %w[stamp_like], result[:unswappable].map(&:id)
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
