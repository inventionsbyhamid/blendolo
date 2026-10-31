# Translates between our neutral vocabulary (docs/effects-vocabulary.md) and YouCam's, in one place.
#
# Neutral effect (Looks::EffectsBuilder), symbol or string keys:
#   category  foundation concealer blush bronzer contour highlighter eyebrows eye_shadow eye_liner eyelashes
#             lip_color lip_liner
#   colour    "#RRGGBB", or a list of them: one palette per colour
#   intensity 0..100, how strong the colour is
#   texture   the finish (one the category can't take falls back to matte)
#   pattern   a pattern id from the provider's public catalog (Appearance::Provider#patterns), or the lip shape
#   mode      eyebrows: "shape" (draw a new brow) or "color" (tint your own, no pattern); lip_color: the lip style
#   optional  coverage, glow, shimmer, gloss, transparency (0..100) and shape ({curvature:, thickness:, definition:}
#             for eyebrows, {thickness:, smoothness:} for lip_liner)
#
# An optional setting left out takes the value the recorded live calls used. Skin smoothing is never sent, so the
# provider's own default (50) applies.
module Appearance::Youcam::Mapper
  CATEGORIES = %w[
    foundation concealer blush bronzer contour highlighter eyebrows eye_shadow eye_liner eyelashes lip_color lip_liner
  ].freeze
  TEXTURES = {
    "blush" => %w[matte satin shimmer], "eyebrows" => %w[matte shimmer],
    "eye_shadow" => %w[matte shimmer metallic], "eye_liner" => %w[matte shimmer metallic],
    "lip_color" => %w[matte satin sheer gloss shimmer metallic holographic], "lip_liner" => %w[matte satin]
  }.freeze
  LIP_FINISH = { "sheer" => { "gloss" => 40, "transparency" => 60 }, "gloss" => { "gloss" => 60, "transparency" => 30 } }.freeze
  BROW_SHAPE = { "curvature" => 0, "thickness" => 10, "definition" => 55 }.freeze
  LIP_LINER_SHAPE = { "thickness" => 50, "smoothness" => 50 }.freeze
  FOUNDATION_GLOW = 30
  BLUSH_SATIN_GLOW = 30
  HEX = /\A#?\h{6}\z/

  REASONS = {
    "error_multiple_people" => :many_faces,
    "error_face_position_too_small" => :face_too_small,
    "error_face_angle_invalid" => :bad_pose, "error_large_face_angle" => :bad_pose, "error_pose" => :bad_pose,
    "error_face_pose" => :bad_pose, "error_face_position_invalid" => :bad_pose,
    "error_face_position_out_of_boundary" => :bad_pose,
    "error_below_min_image_size" => :bad_image, "error_decode_image" => :bad_image,
    "error_download_image" => :bad_image, "error_nsfw_content_detected" => :bad_image,
    "error_face_parsing" => :bad_image, "error_unsupport_ratio" => :bad_image,
    "error_exceed_max_image_size" => :too_large, "exceed_max_filesize" => :too_large,
    "CreditInsufficiency" => :out_of_units, "TaskTimeout" => :timeout
  }.freeze
  # Transfer errors name the side: error_src_* is today's photo, error_ref_* the reference.
  SIDED_REASONS = {
    "no_face" => :no_face, "face_too_small" => :face_too_small, "eye_closed" => :eyes_closed,
    "eye_occluded" => :eyes_closed, "large_face_angle" => :bad_pose, "lip_occluded" => :bad_pose
  }.freeze

  module_function

  # Neutral effects -> YouCam makeup-vto effects[] (string keys, ready for JSON).
  def effects(neutral)
    neutral.map { |effect| effect(effect.to_h.deep_stringify_keys) }
  end

  def reason(code)
    code = code.to_s
    return :bad_image if code.start_with?("error_inappropriate_ref")

    REASONS[code] || SIDED_REASONS[code.sub(/\Aerror_(src_|ref_)?/, "")] || :provider_error
  end

  def about(code)
    case code.to_s
    when /\Aerror_src_/ then :photo
    when /\Aerror_(ref_|inappropriate_ref)/ then :reference
    end
  end

  def effect(neutral)
    category = neutral["category"].to_s
    raise ArgumentError, "unknown effect category #{category.inspect}" unless category.in?(CATEGORIES)

    send(:"#{category}_effect", neutral, setting(neutral, "intensity", 50))
  end

  def foundation_effect(neutral, intensity)
    { "category" => "foundation", "palettes" => palettes(neutral) do
      { "colorIntensity" => intensity, "glowIntensity" => setting(neutral, "glow", FOUNDATION_GLOW),
        "coverageIntensity" => setting(neutral, "coverage", intensity) }
    end }
  end

  def concealer_effect(neutral, intensity)
    { "category" => "concealer", "palettes" => palettes(neutral) do
      { "colorIntensity" => intensity, "colorUnderEyeIntensity" => intensity,
        "coverageLevel" => setting(neutral, "coverage", intensity) }
    end }
  end

  def blush_effect(neutral, intensity)
    texture = texture(neutral)
    glow = setting(neutral, "glow", texture == "satin" ? BLUSH_SATIN_GLOW : nil)
    patterned("blush", neutral) { { "texture" => texture, "colorIntensity" => intensity, "glowStrength" => glow }.compact }
  end

  def bronzer_effect(neutral, intensity) = patterned("bronzer", neutral) { { "colorIntensity" => intensity } }
  def contour_effect(neutral, intensity) = patterned("contour", neutral) { { "colorIntensity" => intensity } }
  def eyelashes_effect(neutral, intensity) = patterned("eyelashes", neutral) { { "colorIntensity" => intensity } }

  # shimmer fills all three shimmer fields; 0 is none.
  def highlighter_effect(neutral, intensity)
    shimmer = setting(neutral, "shimmer", 0)
    patterned("highlighter", neutral) do
      { "colorIntensity" => intensity, "glowIntensity" => setting(neutral, "glow", intensity),
        "shimmerIntensity" => shimmer, "shimmerDensity" => shimmer, "shimmerSize" => shimmer }
    end
  end

  def eye_shadow_effect(neutral, intensity)
    patterned("eye_shadow", neutral) { { "texture" => texture(neutral), "colorIntensity" => intensity } }
  end

  def eye_liner_effect(neutral, intensity)
    patterned("eye_liner", neutral) { { "texture" => texture(neutral), "colorIntensity" => intensity } }
  end

  def lip_liner_effect(neutral, intensity)
    shape = LIP_LINER_SHAPE.merge(neutral["shape"].to_h.compact)
    patterned("lip_liner", neutral) do
      { "texture" => texture(neutral), "colorIntensity" => intensity,
        "thickness" => shape["thickness"].to_i.clamp(0, 100), "smoothness" => shape["smoothness"].to_i.clamp(0, 100) }
    end
  end

  def eyebrows_effect(neutral, intensity)
    pattern = if neutral["mode"].to_s == "color"
      { "type" => "color" }
    else
      shape = BROW_SHAPE.merge(neutral["shape"].to_h.compact)
      { "type" => "shape", "name" => pattern_name(neutral), "curvature" => shape["curvature"].to_i.clamp(-100, 100),
        "thickness" => shape["thickness"].to_i.clamp(-100, 100), "definition" => shape["definition"].to_i.clamp(0, 100) }
    end
    { "category" => "eyebrows", "pattern" => pattern,
      "palettes" => palettes(neutral) { { "colorIntensity" => intensity, "texture" => texture(neutral) } } }
  end

  # Sheer and gloss lips need gloss and transparency; left out, they take the live check's values.
  def lip_color_effect(neutral, intensity)
    texture = texture(neutral)
    finish = LIP_FINISH.fetch(texture, {})
    extra = { "gloss" => setting(neutral, "gloss", finish["gloss"]),
              "transparencyIntensity" => setting(neutral, "transparency", finish["transparency"]) }.compact
    { "category" => "lip_color", "shape" => { "name" => neutral["pattern"].presence || "original" },
      "style" => { "type" => neutral["mode"].presence || "full" },
      "palettes" => palettes(neutral) { { "texture" => texture, "colorIntensity" => intensity, **extra } } }
  end

  def patterned(category, neutral, &palette)
    { "category" => category, "pattern" => { "name" => pattern_name(neutral) }, "palettes" => palettes(neutral, &palette) }
  end

  # One palette per colour (a pattern with N colours takes exactly N palettes).
  def palettes(neutral)
    Array(neutral["colour"]).map do |colour|
      raise ArgumentError, "colour must be #RRGGBB, got #{colour.inspect}" unless colour.to_s.match?(HEX)

      { "color" => colour, **yield }
    end
  end

  def pattern_name(neutral)
    neutral["pattern"].presence || raise(ArgumentError, "#{neutral['category']} needs a pattern")
  end

  def texture(neutral)
    texture = neutral["texture"].to_s
    texture.in?(TEXTURES.fetch(neutral["category"])) ? texture : "matte"
  end

  # A 0..100 setting, or the default when the effect leaves it out.
  def setting(neutral, key, default)
    value = neutral[key]
    value.nil? ? default : value.to_i.clamp(0, 100)
  end
end
