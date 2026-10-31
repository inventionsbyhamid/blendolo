require "test_helper"

class Appearance::Youcam::MapperTest < ActiveSupport::TestCase
  Mapper = Appearance::Youcam::Mapper

  FULL_LOOK = [
    { category: "foundation", colour: "#7E4A30", intensity: 35 },
    { category: "blush", colour: "#B5524A", intensity: 45, texture: "matte", pattern: "Oblique1" },
    { category: "eye_shadow", colour: "#7A4E3A", intensity: 55, texture: "matte", pattern: "1color6" },
    { category: "eye_liner", colour: "#111111", intensity: 90, texture: "matte", pattern: "OpenWings2" },
    { category: "eyelashes", colour: "#000000", intensity: 85, pattern: "Natural2" },
    { category: "eyebrows", colour: "#2B1B14", intensity: 60, texture: "matte", pattern: "SoftArch3", mode: "shape" },
    { category: "lip_color", colour: "#8E1F2F", intensity: 85, texture: "matte", pattern: "original", mode: "full" }
  ].freeze

  test "effects mapping matches live request" do
    assert_equal live_effects("makeup_vto_7effects_create.json"), Mapper.effects(FULL_LOOK)

    easy = FULL_LOOK.map do |effect|
      case effect[:category]
      when "eye_liner" then effect.merge(colour: "#3A2A22", intensity: 70, pattern: "Smoke4")
      when "lip_color" then effect.merge(colour: "#A84452", intensity: 45, texture: "sheer")
      else effect
      end
    end
    assert_equal live_effects("makeup_vto_easy_create.json"), Mapper.effects(easy)
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
