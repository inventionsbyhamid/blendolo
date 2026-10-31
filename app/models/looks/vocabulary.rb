module Looks
  # Our own words for a makeup effect, independent of any rendering provider. docs/effects-vocabulary.md
  # explains each key; the provider adapter translates them.
  #
  #   { category:, colour:, intensity:, texture:, pattern:, mode: } plus, only when set,
  #   coverage:, glow:, shimmer:, gloss:, transparency:, shape:
  module Vocabulary
    CATEGORIES = %w[foundation concealer blush bronzer contour highlighter eyebrows eye_shadow eye_liner eyelashes
                    lip_color lip_liner].freeze
    CORE_KEYS = %i[category colour intensity texture pattern mode].freeze
    OPTIONAL_KEYS = %i[coverage glow shimmer gloss transparency shape].freeze
    KEYS = (CORE_KEYS + OPTIONAL_KEYS).freeze

    # Base categories take the person's skin colour, so they never carry a default colour.
    BASE = %w[foundation concealer].freeze
    WITH_PATTERN = %w[blush bronzer contour highlighter eyebrows eye_shadow eye_liner eyelashes lip_color
                      lip_liner].freeze

    TEXTURES = {
      "blush" => %w[matte satin],
      "eyebrows" => %w[matte],
      "eye_shadow" => %w[matte],
      "eye_liner" => %w[matte],
      "lip_color" => %w[matte satin sheer gloss],
      "lip_liner" => %w[matte satin]
    }.freeze

    MODES = { "eyebrows" => %w[shape color], "lip_color" => %w[full] }.freeze

    # Optional keys each category understands, and the ones a texture or mode makes required.
    OPTIONAL = {
      "foundation" => %i[coverage glow],
      "concealer" => %i[coverage],
      "blush" => %i[glow],
      "highlighter" => %i[glow shimmer],
      "eyebrows" => %i[shape],
      "lip_color" => %i[gloss transparency],
      "lip_liner" => %i[shape]
    }.freeze
    REQUIRED = {
      [ "blush", "satin" ] => %i[glow],
      [ "lip_color", "sheer" ] => %i[gloss transparency],
      [ "lip_color", "gloss" ] => %i[gloss transparency],
      [ "eyebrows", "shape" ] => %i[shape]
    }.freeze
    SHAPE_KEYS = { "eyebrows" => %i[curvature thickness definition], "lip_liner" => %i[thickness smoothness] }.freeze
    SHAPE_RANGES = { curvature: -100..100, thickness: -100..100, definition: 0..100, smoothness: 0..100 }.freeze

    HEX = /\A#\h{6}\z/
    LEVEL = 0..100

    module_function

    # An effect with symbol keys all the way down, as it reads back from JSON (string keys) or as built.
    def normalise(effect)
      effect.to_h.deep_symbolize_keys
    end

    # Problems with one effect, as sentences. Empty when the effect is valid. String or symbol keys.
    def errors(effect)
      effect = normalise(effect)
      category = effect[:category]
      return [ "unknown category #{category.inspect}" ] unless CATEGORIES.include?(category)

      errors = []
      errors << "unknown keys #{(effect.keys - KEYS).inspect}" if (effect.keys - KEYS).any?
      errors << "missing #{(CORE_KEYS - effect.keys).inspect}" if (CORE_KEYS - effect.keys).any?
      errors << "colour must be #RRGGBB or a list of them" unless colours?(effect[:colour])
      errors << "intensity must be 0..100" unless level?(effect[:intensity])
      errors << "texture #{effect[:texture].inspect} not allowed" unless TEXTURES.fetch(category, [ nil ]).include?(effect[:texture])
      errors << "mode #{effect[:mode].inspect} not allowed" unless MODES.fetch(category, [ nil ]).include?(effect[:mode])
      errors.concat(pattern_errors(effect))
      errors.concat(optional_errors(effect))
    end

    def valid?(effect)
      errors(effect).empty?
    end

    def colours?(colour)
      list = Array(colour)
      list.any? && list.all? { |hex| hex.is_a?(String) && HEX.match?(hex) }
    end

    def level?(value)
      value.is_a?(Integer) && LEVEL.cover?(value)
    end

    def pattern_errors(effect)
      category = effect[:category]
      wants_pattern = WITH_PATTERN.include?(category) && !(category == "eyebrows" && effect[:mode] == "color")

      if wants_pattern && !effect[:pattern].is_a?(String)
        [ "#{category} needs a pattern" ]
      elsif !wants_pattern && !effect[:pattern].nil?
        [ "#{category} takes no pattern here" ]
      else
        []
      end
    end

    def optional_errors(effect)
      category = effect[:category]
      present = OPTIONAL_KEYS.select { |key| effect.key?(key) }
      errors = []
      errors << "#{category} doesn't take #{(present - OPTIONAL.fetch(category, [])).inspect}" if (present - OPTIONAL.fetch(category, [])).any?
      missing = REQUIRED.fetch([ category, effect[:texture] ], []) + REQUIRED.fetch([ category, effect[:mode] ], []) - present
      errors << "#{category} needs #{missing.inspect}" if missing.any?
      (present - [ :shape ]).each { |key| errors << "#{key} must be 0..100" unless level?(effect[key]) }
      errors.concat(shape_errors(category, effect[:shape])) if effect.key?(:shape)
      errors
    end

    def shape_errors(category, shape)
      expected = SHAPE_KEYS.fetch(category, [])
      return [ "shape must have #{expected.inspect}" ] unless shape.is_a?(Hash) && shape.keys.sort == expected.sort

      shape.filter_map { |key, value| "shape #{key} out of range" unless value.is_a?(Integer) && SHAPE_RANGES.fetch(key).cover?(value) }
    end
  end
end
