require "test_helper"
require_relative "../../support/copy_rules"

class Looks::CatalogueTest < ActiveSupport::TestCase
  include CopyRules

  def test_the_eight_looks
    assert_equal [ "Everyday fresh", "The red lip", "Soft smoky evening", "Rosy glow", "Bold berry",
                   "Brows and mascara", "Wedding guest", "Barely there" ], Looks::Catalogue.all.map(&:name)
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
