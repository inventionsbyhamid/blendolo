require "test_helper"
require_relative "../../support/copy_rules"

class Looks::CatalogueTest < ActiveSupport::TestCase
  include CopyRules

  def test_the_eight_looks
    assert_equal [ "Everyday fresh", "The red lip", "Soft smoky evening", "Rosy glow", "Bold berry",
                   "Brows and mascara", "Wedding guest", "Barely there" ], Looks::Catalogue.all.map(&:name)
  end

  def test_every_look_has_a_step_you_need
    Looks::Catalogue.all.each do |look|
      assert look.steps.any? { |step| !step.optional }, "#{look.key} has only optional steps, so it has no grade"
    end
  end

  def test_wrapping_a_step_keeps_it_optional
    step = Ease::StepCatalogue.fetch("mascara_upper").as_optional
    assert Looks::LookStep.wrap(step).optional
    assert Looks::LookStep.wrap(step).step.optional?
  end

  def test_every_look_step_exists_in_catalogue
    Looks::Catalogue.all.each do |look|
      look.steps.each do |look_step|
        assert Ease::StepCatalogue.key?(look_step.step_id), "#{look.key}: #{look_step.step_id}"
      end
      assert_equal look.steps.map(&:step_id).uniq, look.steps.map(&:step_id), "#{look.key} repeats a step"
    end
  end

  def test_look_colours_fit_their_steps
    Looks::Catalogue.all.flat_map(&:steps).each do |look_step|
      default = look_step.step.effect&.fetch(:colour, nil)
      expected = default.is_a?(Array) ? default.size : 1
      assert_equal expected, Array(look_step.colour || default || "#000000").size, look_step.step_id
      assert_includes 0..100, look_step.intensity if look_step.intensity
    end
  end

  def test_base_steps_never_carry_a_colour
    Looks::Catalogue.all.flat_map(&:steps).each do |look_step|
      next unless Looks::Vocabulary::BASE.include?(look_step.step.category)

      assert_nil look_step.colour, "#{look_step.step_id} takes the person's skin colour"
    end
  end

  def test_each_look_renders_one_effect_per_category
    Looks::Catalogue.all.each do |look|
      categories = look.steps.map(&:step).filter_map(&:category)

      assert_equal categories.uniq, categories, look.key
    end
  end

  def test_every_look_has_a_thumbnail_path_and_short_warm_copy
    Looks::Catalogue.all.each do |look|
      assert_equal "looks/#{look.key}.jpg", look.thumbnail
      [ look.name, look.blurb ].each { assert_copy_follows_house_rules it, look.key }
      assert_operator look.blurb.split.size, :<=, 20, look.key
    end
  end

  def test_fetch_by_key
    assert_equal "The red lip", Looks::Catalogue.fetch(:red_lip).name
    assert_raises(Looks::Catalogue::UnknownLook) { Looks::Catalogue.fetch("glitter") }
  end

  OPTIONAL = %w[mascara_upper mascara_lower eyelash_curler strip_lashes magnetic_liner_lashes setting_spray].freeze
  WORDS = %w[Hard Tricky Some\ care Easy].freeze

  def test_mascara_lashes_curler_and_setting_spray_are_optional_in_every_look
    Looks::Catalogue.all.flat_map(&:steps).each do |look_step|
      assert_equal OPTIONAL.include?(look_step.step_id), look_step.optional, look_step.step_id
      assert_equal look_step.optional, look_step.step.optional?
    end
  end

  def test_red_lip_easy_for_tremor_is_better_than_hard
    rosa = YAML.load_file(Rails.root.join("config/blendolo/examples.yml")).dig("people", "rosa")
    profile = Ease::HandProfile.new(**rosa.fetch("hands").symbolize_keys)
    look = Looks::Catalogue.fetch(rosa.fetch("chosen_look"))
    assert_equal "red_lip", look.key

    classic = Ease::Words.for(Ease::Scorer.look(look.ease_steps, profile)[:ease])
    easy_result = Ease::Scorer.look(look.easy_steps(profile).map(&:step), profile)
    easy = Ease::Words.for(easy_result[:ease])

    assert_equal "Hard", classic
    assert_operator WORDS.index(easy), :>=, WORDS.index(classic) + 1, "#{classic} -> #{easy}"
    assert_equal %w[mascara_upper], easy_result[:optional].map { it[:step].id }, "mascara is reported, not graded"
  end

  def test_optional_survives_a_stored_routine_and_a_swap
    wedding = Looks::Catalogue.fetch(:wedding_guest)
    easy = wedding.easy_steps(Ease::HandProfile.new)
    mascara = easy.find { it.step_id == "mascara_upper" }

    assert mascara.optional, "strip lashes swapped for mascara stay optional"
    stored = JSON.parse(easy.map(&:to_h).to_json)
    assert_equal easy, stored.map { Looks::LookStep.wrap(it) }
  end

  def test_easy_versions_are_easier_for_every_look_and_profile
    answers = [ 0, 1, 2 ]
    profiles = answers.product(answers, answers, answers, answers).map do |tremor, pinch, one_hand, fatigue, near_vision|
      Ease::HandProfile.new(tremor:, pinch:, one_hand:, fatigue:, near_vision:)
    end

    Looks::Catalogue.all.product(profiles).each do |look, profile|
      classic = Ease::Scorer.look(look.ease_steps, profile)[:ease]
      easy = Ease::Scorer.look(look.easy_steps(profile).map(&:step), profile)[:ease]

      assert_operator easy, :>=, classic, "#{look.key} #{profile.to_h}"
    end
  end
end
