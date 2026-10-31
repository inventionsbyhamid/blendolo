# Translates between our neutral vocabulary and YouCam's, in one place.
#
# Neutral effect (Looks::EffectsBuilder): { category:, colour:, intensity:, texture:, pattern:, mode: }
#   category  foundation concealer blush bronzer contour highlighter eyebrows eye_shadow eye_liner eyelashes
#             lip_color lip_liner
#   colour    "#RRGGBB", or a list of them for a pattern with several colours
#   intensity 0..100
#   texture   matte, satin, sheer, gloss, shimmer, metallic (a texture the category can't take falls back to matte)
#   pattern   a pattern label from the provider's public catalog (Appearance::Provider#patterns), or the lip shape
#   mode      eyebrows: "shape" (draw a new brow) or "color" (tint your own); lip_color: "full", "ombre", "twoTone"
#
# The fixed numbers below (foundation glow, brow shape, sheer lip gloss) are the ones the recorded live calls used.
module Appearance::Youcam::Mapper
  CATEGORIES = %w[
    foundation concealer blush bronzer contour highlighter eyebrows eye_shadow eye_liner eyelashes lip_color lip_liner
  ].freeze
  TEXTURES = {
    "blush" => %w[matte satin shimmer], "eyebrows" => %w[matte shimmer],
    "eye_shadow" => %w[matte shimmer metallic], "eye_liner" => %w[matte shimmer metallic],
    "lip_color" => %w[matte satin sheer gloss shimmer metallic holographic], "lip_liner" => %w[matte satin]
  }.freeze
  LIP_FINISH = { "sheer" => { "gloss" => 40, "transparencyIntensity" => 60 }, "gloss" => { "gloss" => 60 } }.freeze
  BROW_SHAPE = { "curvature" => 0, "thickness" => 10, "definition" => 55 }.freeze
  FOUNDATION_GLOW = 30
  BLUSH_SATIN_GLOW = 30
  HIGHLIGHTER_SHIMMER = { "shimmerIntensity" => 20, "shimmerDensity" => 20, "shimmerSize" => 20 }.freeze
  LIP_LINER_LINE = { "thickness" => 50, "smoothness" => 50 }.freeze
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
    neutral.map { |effect| effect(effect.to_h.stringify_keys) }
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

    send(:"#{category}_effect", neutral, intensity(neutral))
  end

  def foundation_effect(neutral, intensity)
    { "category" => "foundation", "palettes" => palettes(neutral) { { "colorIntensity" => intensity,
      "glowIntensity" => FOUNDATION_GLOW, "coverageIntensity" => intensity } } }
  end

  def concealer_effect(neutral, intensity)
    { "category" => "concealer", "palettes" => palettes(neutral) { { "colorIntensity" => intensity,
      "colorUnderEyeIntensity" => intensity, "coverageLevel" => intensity } } }
  end

  def blush_effect(neutral, intensity)
    texture = texture(neutral)
    extra = texture == "satin" ? { "glowStrength" => BLUSH_SATIN_GLOW } : {}
    patterned("blush", neutral) { { "texture" => texture, "colorIntensity" => intensity, **extra } }
  end

  def bronzer_effect(neutral, intensity) = patterned("bronzer", neutral) { { "colorIntensity" => intensity } }
  def contour_effect(neutral, intensity) = patterned("contour", neutral) { { "colorIntensity" => intensity } }
  def eyelashes_effect(neutral, intensity) = patterned("eyelashes", neutral) { { "colorIntensity" => intensity } }

  def highlighter_effect(neutral, intensity)
    patterned("highlighter", neutral) do
      { "colorIntensity" => intensity, "glowIntensity" => intensity, **HIGHLIGHTER_SHIMMER }
    end
  end

  def eye_shadow_effect(neutral, intensity)
    patterned("eye_shadow", neutral) { { "texture" => texture(neutral), "colorIntensity" => intensity } }
  end

  def eye_liner_effect(neutral, intensity)
    patterned("eye_liner", neutral) { { "texture" => texture(neutral), "colorIntensity" => intensity } }
  end

  def lip_liner_effect(neutral, intensity)
    patterned("lip_liner", neutral) do
      { "texture" => texture(neutral), "colorIntensity" => intensity, **LIP_LINER_LINE }
    end
  end

  def eyebrows_effect(neutral, intensity)
    pattern = if neutral["mode"].to_s == "color"
      { "type" => "color" }
    else
      { "type" => "shape", "name" => pattern_name(neutral), **BROW_SHAPE }
    end
    { "category" => "eyebrows", "pattern" => pattern,
      "palettes" => palettes(neutral) { { "colorIntensity" => intensity, "texture" => texture(neutral) } } }
  end

  def lip_color_effect(neutral, intensity)
    texture = texture(neutral)
    { "category" => "lip_color", "shape" => { "name" => neutral["pattern"].presence || "original" },
      "style" => { "type" => neutral["mode"].presence || "full" },
      "palettes" => palettes(neutral) do
        { "texture" => texture, "colorIntensity" => intensity, **LIP_FINISH.fetch(texture, {}) }
      end }
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

  def intensity(neutral)
    (neutral["intensity"] || 50).to_i.clamp(0, 100)
  end
end
