require "test_helper"

class Appearance::Youcam::MapperTest < ActiveSupport::TestCase
  Mapper = Appearance::Youcam::Mapper

  # The seven effect look from the effects vocabulary (docs/effects-vocabulary.md), which the live check sent.
  FULL_LOOK = [
    { category: "foundation", colour: "#7E4A30", intensity: 35, texture: nil, pattern: nil, mode: nil,
      coverage: 35, glow: 30 },
    { category: "blush", colour: "#B5524A", intensity: 45, texture: "matte", pattern: "Oblique1", mode: nil },
    { category: "eye_shadow", colour: "#7A4E3A", intensity: 55, texture: "matte", pattern: "1color6", mode: nil },
    { category: "eye_liner", colour: "#111111", intensity: 90, texture: "matte", pattern: "OpenWings2", mode: nil },
    { category: "eyelashes", colour: "#000000", intensity: 85, texture: nil, pattern: "Natural2", mode: nil },
    { category: "eyebrows", colour: "#2B1B14", intensity: 60, texture: "matte", pattern: "SoftArch3", mode: "shape",
      shape: { curvature: 0, thickness: 10, definition: 55 } },
    { category: "lip_color", colour: "#8E1F2F", intensity: 85, texture: "matte", pattern: "original", mode: "full" }
  ].freeze

  test "effects mapping matches live request" do
    assert_equal live_effects("makeup_vto_7effects_create.json"), Mapper.effects(FULL_LOOK)

    easy = FULL_LOOK.map do |effect|
      case effect[:category]
      when "eye_liner" then effect.merge(colour: "#3A2A22", intensity: 70, pattern: "Smoke4")
      when "lip_color" then effect.merge(colour: "#A84452", intensity: 45, texture: "sheer", gloss: 40, transparency: 60)
      else effect
      end
    end
    assert_equal live_effects("makeup_vto_easy_create.json"), Mapper.effects(easy)
  end

  test "maps the optional settings of the vocabulary" do
    effects = Mapper.effects([
      { category: "foundation", colour: "#7E4A30", intensity: 40, coverage: 25, glow: 10 },
      { category: "concealer", colour: "#C99A7E", intensity: 40, coverage: 70 },
      { category: "blush", colour: "#D77A6E", intensity: 40, texture: "satin", pattern: "Round1", glow: 25 },
      { category: "highlighter", colour: "#F3E3D0", intensity: 40, pattern: "Oval2", glow: 50, shimmer: 30 },
      { category: "eyebrows", colour: "#3B2A20", intensity: 60, texture: "matte", pattern: "SoftArch3", mode: "shape",
        shape: { curvature: 20, thickness: -10, definition: 70 } },
      { category: "lip_color", colour: "#B0182A", intensity: 45, texture: "sheer", pattern: "original", mode: "full",
        gloss: 35, transparency: 60 },
      { category: "lip_liner", colour: "#8E1424", intensity: 70, texture: "matte", pattern: "Natural1",
        shape: { thickness: 30, smoothness: 80 } }
    ].map(&:deep_stringify_keys))

    palettes = effects.map { it["palettes"].sole }
    assert_equal [ 40, 10, 25 ], palettes[0].values_at("colorIntensity", "glowIntensity", "coverageIntensity")
    assert_equal [ 40, 40, 70 ], palettes[1].values_at("colorIntensity", "colorUnderEyeIntensity", "coverageLevel")
    assert_equal 25, palettes[2]["glowStrength"]
    assert_equal [ 50, 30, 30, 30 ], palettes[3].values_at("glowIntensity", "shimmerIntensity", "shimmerDensity", "shimmerSize")
    assert_equal({ "type" => "shape", "name" => "SoftArch3", "curvature" => 20, "thickness" => -10, "definition" => 70 },
      effects[4]["pattern"])
    assert_equal [ 35, 60 ], palettes[5].values_at("gloss", "transparencyIntensity")
    assert_equal [ 30, 80 ], palettes[6].values_at("thickness", "smoothness")
  end

  test "maps the red lip example of the vocabulary, classic and easy" do
    easy = Mapper.effects([
      { category: "eyebrows", colour: "#3B2A20", intensity: 45, texture: "matte", pattern: nil, mode: "color" },
      { category: "eye_liner", colour: "#2B1D16", intensity: 88, texture: "matte", pattern: "Smoke4", mode: nil },
      { category: "eyelashes", colour: "#000000", intensity: 85, texture: nil, pattern: "Natural2", mode: nil },
      { category: "lip_color", colour: "#B0182A", intensity: 45, texture: "sheer", pattern: "original", mode: "full",
        gloss: 35, transparency: 60 }
    ])

    assert_equal({ "type" => "color" }, easy[0]["pattern"])
    assert_equal({ "color" => "#000000", "colorIntensity" => 85 }, easy[2]["palettes"].sole)
    assert_equal({ "color" => "#B0182A", "texture" => "sheer", "colorIntensity" => 45, "gloss" => 35,
      "transparencyIntensity" => 60 }, easy[3]["palettes"].sole)
  end

  test "takes string keys, as stored in jsonb" do
    assert_equal Mapper.effects(FULL_LOOK), Mapper.effects(FULL_LOOK.map(&:deep_stringify_keys))
  end

  test "fills every field the api requires for the other categories" do
    effects = Mapper.effects([
      { category: "concealer", colour: "#C99A7E", intensity: 40 },
      { category: "bronzer", colour: "#8C5A3C", intensity: 30, pattern: "Bronzer1" },
      { category: "contour", colour: "#6E4A36", intensity: 30, pattern: "Oval1" },
      { category: "highlighter", colour: "#F3E3D0", intensity: 40, pattern: "Oval2" },
      { category: "lip_liner", colour: "#7A2333", intensity: 60, pattern: "Natural" },
      { category: "blush", colour: "#D77A6E", intensity: 40, texture: "satin", pattern: "Round1" },
      { category: "eyebrows", colour: "#3B2A20", intensity: 50, mode: "color" },
      { category: "eye_shadow", colour: [ "#7A4E3A", "#C9A27E" ], intensity: 50, pattern: "2colors1" }
    ])

    assert_equal({ "color" => "#C99A7E", "colorIntensity" => 40, "colorUnderEyeIntensity" => 40, "coverageLevel" => 40 },
      effects[0]["palettes"].sole)
    assert_equal({ "name" => "Bronzer1" }, effects[1]["pattern"])
    assert_equal({ "color" => "#6E4A36", "colorIntensity" => 30 }, effects[2]["palettes"].sole)
    assert_equal %w[color colorIntensity glowIntensity shimmerDensity shimmerIntensity shimmerSize],
      effects[3]["palettes"].sole.keys.sort
    assert_equal %w[color colorIntensity smoothness texture thickness], effects[4]["palettes"].sole.keys.sort
    assert_equal 30, effects[5]["palettes"].sole["glowStrength"]
    assert_equal({ "type" => "color" }, effects[6]["pattern"])
    assert_equal %w[#7A4E3A #C9A27E], effects[7]["palettes"].map { it["color"] }
  end

  test "clamps intensity to 0 to 100 and rejects what it can't map" do
    assert_equal 100, Mapper.effects([ { category: "lip_color", colour: "#8E1F2F", intensity: 140 } ])
      .sole["palettes"].sole["colorIntensity"]
    assert_raises(ArgumentError) { Mapper.effects([ { category: "glitter", colour: "#FFFFFF", intensity: 10 } ]) }
    assert_raises(ArgumentError) { Mapper.effects([ { category: "blush", colour: "pink", intensity: 10, pattern: "Round1" } ]) }
  end

  test "maps provider error codes to reasons and the photo they concern" do
    {
      "error_no_face" => [ :no_face, nil ],
      "error_src_no_face" => [ :no_face, :photo ],
      "error_ref_no_face" => [ :no_face, :reference ],
      "error_multiple_people" => [ :many_faces, nil ],
      "error_face_position_too_small" => [ :face_too_small, nil ],
      "error_ref_face_too_small" => [ :face_too_small, :reference ],
      "error_src_eye_closed" => [ :eyes_closed, :photo ],
      "error_ref_eye_occluded" => [ :eyes_closed, :reference ],
      "error_face_angle_invalid" => [ :bad_pose, nil ],
      "error_src_large_face_angle" => [ :bad_pose, :photo ],
      "error_face_position_out_of_boundary" => [ :bad_pose, nil ],
      "error_inappropriate_ref_case01" => [ :bad_image, :reference ],
      "error_decode_image" => [ :bad_image, nil ],
      "error_exceed_max_image_size" => [ :too_large, nil ],
      "exceed_max_filesize" => [ :too_large, nil ],
      "CreditInsufficiency" => [ :out_of_units, nil ],
      "TaskTimeout" => [ :timeout, nil ],
      "error_inference" => [ :provider_error, nil ],
      "something_new" => [ :provider_error, nil ]
    }.each do |code, (reason, about)|
      assert_equal [ reason, about ], [ Mapper.reason(code), Mapper.about(code) ], code
    end
  end

  private
    def live_effects(name)
      JSON.parse(file_fixture("youcam/makeup/#{name}").read).dig("request", "body", "effects")
    end
end
