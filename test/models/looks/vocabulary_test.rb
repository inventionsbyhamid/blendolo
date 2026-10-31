require "test_helper"

class Looks::VocabularyTest < ActiveSupport::TestCase
  def effect(**overrides)
    { category: "blush", colour: "#B5524A", intensity: 45, texture: "matte", pattern: "Oblique1", mode: nil }
      .merge(overrides)
  end

  def test_a_complete_effect_is_valid
    assert_empty Looks::Vocabulary.errors(effect)
    assert Looks::Vocabulary.valid?(effect(texture: "satin", glow: 30))
    assert Looks::Vocabulary.valid?(category: "foundation", colour: "#7E4A30", intensity: 35, texture: nil,
                                    pattern: nil, mode: nil, glow: 30, coverage: 35)
    assert Looks::Vocabulary.valid?(category: "eyebrows", colour: "#2B1B14", intensity: 60, texture: "matte",
                                    pattern: "SoftArch3", mode: "shape",
                                    shape: { curvature: 0, thickness: 10, definition: 55 })
    assert Looks::Vocabulary.valid?(category: "eyebrows", colour: "#3B2A20", intensity: 45, texture: "matte",
                                    pattern: nil, mode: "color")
    assert Looks::Vocabulary.valid?(category: "eye_shadow", colour: [ "#C9A48A", "#6B4632" ], intensity: 55,
                                    texture: "matte", pattern: "2colors1", mode: nil)
  end

  def test_rejects_unknown_categories_keys_and_values
    assert_includes Looks::Vocabulary.errors(effect(category: "mascara")).first, "unknown category"
    assert_not Looks::Vocabulary.valid?(effect(sparkle: 10))
    assert_not Looks::Vocabulary.valid?(effect(colour: "red"))
    assert_not Looks::Vocabulary.valid?(effect(intensity: 101))
    assert_not Looks::Vocabulary.valid?(effect(texture: "metallic"))
    assert_not Looks::Vocabulary.valid?(effect(mode: "shape"))
    assert_not Looks::Vocabulary.valid?(effect.except(:mode))
  end

  def test_texture_and_mode_require_their_settings
    assert_not Looks::Vocabulary.valid?(effect(texture: "satin")), "satin blush needs glow"
    sheer = { category: "lip_color", colour: "#A84452", intensity: 45, texture: "sheer", pattern: "original",
              mode: "full" }
    assert_not Looks::Vocabulary.valid?(sheer)
    assert Looks::Vocabulary.valid?(sheer.merge(gloss: 35, transparency: 60))
    assert_not Looks::Vocabulary.valid?(category: "eyebrows", colour: "#2B1B14", intensity: 60, texture: "matte",
                                        pattern: "SoftArch3", mode: "shape")
  end

  def test_patterns_only_where_a_category_takes_one
    assert_not Looks::Vocabulary.valid?(effect(pattern: nil))
    assert_not Looks::Vocabulary.valid?(category: "foundation", colour: "#7E4A30", intensity: 35, texture: nil,
                                        pattern: "Oblique1", mode: nil)
    assert_not Looks::Vocabulary.valid?(category: "eyebrows", colour: "#3B2A20", intensity: 45, texture: "matte",
                                        pattern: "SoftArch3", mode: "color")
  end

  def test_effects_read_back_from_json_with_string_keys_are_valid
    built = Looks::EffectsBuilder.build(Looks::Catalogue.fetch(:red_lip).steps)
    stored = JSON.parse(built.to_json)
    assert_kind_of String, stored.first.keys.first

    stored.each { assert_empty Looks::Vocabulary.errors(it), it.inspect }
    assert_equal built, stored.map { Looks::Vocabulary.normalise(it) }
    assert_not Looks::Vocabulary.valid?(stored.first.merge("intensity" => 300))
  end

  def test_optional_settings_belong_to_their_categories
    assert_not Looks::Vocabulary.valid?(effect(gloss: 30))
    assert_not Looks::Vocabulary.valid?(effect(texture: "satin", glow: 130))
    assert_not Looks::Vocabulary.valid?(category: "lip_liner", colour: "#7A1A28", intensity: 70, texture: "matte",
                                        pattern: "Natural1", mode: nil, shape: { curvature: 0 })
  end
end
