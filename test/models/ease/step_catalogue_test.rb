require "test_helper"
require_relative "../../support/copy_rules"

class Ease::StepCatalogueTest < ActiveSupport::TestCase
  include CopyRules

  COPY = %i[name instruction swap_why why_easier product_type].freeze

  setup do
    @steps = Ease::StepCatalogue.all
    @default = Ease::HandProfile.new
  end

  def test_numbers_cover_the_29_table_steps_once
    assert_equal (1..29).to_a, @steps.filter_map(&:number).sort
  end

  def test_fixup_is_the_cotton_bud_step_with_no_effect
    fixup = Ease::StepCatalogue.fixup

    assert_match(/cotton bud/i, fixup.name)
    assert_match(/micellar water/i, fixup.instruction)
    assert_nil fixup.effect
    assert_equal 94, Ease::Scorer.step(fixup, @default)
  end

  def test_dims_are_0_to_3_for_all_seven_dimensions
    @steps.each do |step|
      assert_equal Ease::HandProfile::DIMENSIONS.sort, step.dims.keys.sort, step.id
      step.dims.each_value { assert_includes 0..3, it, step.id }
    end
  end

  def test_every_swap_points_at_a_real_easier_step
    @steps.select(&:swap).each do |step|
      assert step.swap_why.present?, "#{step.id} says why its swap is easier"
      next if step.skip?

      swap = Ease::StepCatalogue.fetch(step.swap_id)
      assert_nil swap.swap, "#{step.id} swaps to #{swap.id}, which must not swap again"
      assert_operator Ease::Scorer.step(swap, @default), :>, Ease::Scorer.step(step, @default), step.id
    end
  end

  def test_every_step_has_a_layer_and_an_area
    @steps.each do |step|
      assert_includes Ease::Step::LAYERS, step.layer, step.id
      assert step.area.present?, step.id
    end
    assert_equal %w[finish finish], %w[fixup setting_spray].map { Ease::StepCatalogue.fetch(it).layer }
  end

  def test_only_swaps_the_table_names
    assert_nil Ease::StepCatalogue.fetch("brow_stamp").swap, "row 10 names no easier swap"
    assert_nil Ease::StepCatalogue.fetch("magnetic_liner_lashes").swap, "row 23 says it is still hard"
    assert_nil Ease::StepCatalogue.fetch("mascara_upper").swap
  end

  def test_catalogue_is_deeply_frozen
    brow = Ease::StepCatalogue.fetch("brow_pencil")

    assert_predicate brow.effect[:shape], :frozen?
    assert_predicate brow.tips.first, :frozen?
    assert_raises(FrozenError) { brow.effect[:shape][:thickness] = 99 }
  end

  def test_steps_without_a_number_are_swap_targets_or_the_fixup
    targets = @steps.filter_map(&:swap_id)

    @steps.reject(&:number).each do |step|
      assert step.fixup? || targets.include?(step.id), "#{step.id} is a swap target"
    end
  end

  def test_unknown_step_raises
    assert_raises(Ease::StepCatalogue::UnknownStep) { Ease::StepCatalogue.fetch("glitter_cannon") }
  end

  def test_mascara_says_plainly_there_is_no_easy_version_and_gives_the_tips
    mascara = Ease::StepCatalogue.fetch("mascara_upper")

    assert_nil mascara.swap
    assert_match(/no truly easy version/i, mascara.why_easier)
    tips = mascara.tips.join(" ")
    assert_match(/ring/i, tips)
    assert_match(/elbow/i, tips)
    assert_match(/shield/i, tips)
  end

  def test_instructions_are_at_most_12_words
    @steps.each do |step|
      assert_operator step.instruction.split.size, :<=, 12, step.id
    end
  end

  def test_copy_has_no_dashes_or_banned_words
    @steps.each do |step|
      (COPY.filter_map { step.public_send(it) } + step.tips).each do |text|
        assert_copy_follows_house_rules text, step.id
      end
    end
  end
end
