module Looks
  # Colours sampled from a photo come out muted by the light they were taken in (an old print fades a red lip towards
  # brick). We snap each one to the nearest shade we render well, measured with CIE94 colour distance, which weighs a
  # difference in vividness less the more vivid the shade is, so a faded red still finds the red, not the brown.
  module ColourSamplerMapping
    SHADES = {
      lips: {
        "nude" => "#B5776B", "rose" => "#B85C6B", "pink" => "#D46A8A", "coral" => "#E0605A",
        "red" => "#B0182A", "berry" => "#8E1F2F", "plum" => "#6E2A45", "brown" => "#7A3E33"
      },
      lids: {
        "champagne" => "#D9B99B", "gold" => "#B8924A", "taupe" => "#9C8577", "bronze" => "#9A6A3E",
        "brown" => "#6B4632", "plum" => "#6E4A5E", "grey" => "#6F6F73", "navy" => "#2F3A5A", "olive" => "#5E6B48"
      },
      cheeks: {
        "peach" => "#E59A7A", "pink" => "#E58FA5", "rose" => "#C96B7A", "coral" => "#E07B62",
        "berry" => "#A8455A", "bronze" => "#B07A55"
      }
    }.freeze
    REGIONS = SHADES.keys.freeze

    HEX = /\A#?(\h{2})(\h{2})(\h{2})\z/
    D65 = [ 0.95047, 1.0, 1.08883 ].freeze

    module_function

    # { lips:, lids:, cheeks:, skin: } from what the browser sampled. Regions snap to our shades, skin is kept as
    # sampled (it is only ever used as the skin colour). Missing or unreadable colours come back nil.
    def map(sampled)
      sampled = (sampled || {}).to_h.symbolize_keys

      REGIONS.index_with { |region| nearest(region, sampled[region]) }
        .merge(skin: (normalise(sampled[:skin]) if lab(sampled[:skin])))
    end

    # The shade for this region closest to the sampled hex, or nil when there is no usable colour.
    def nearest(region, hex)
      sampled = lab(hex)
      return unless sampled

      SHADES.fetch(region).values.min_by { |shade| distance(sampled, lab(shade)) }
    end

    # CIE94 (graphic arts weights) from a sampled colour to a shade, both [L, a, b]; the shade is the reference.
    def distance(sample, shade)
      chroma = ->(lab) { Math.hypot(lab[1], lab[2]) }
      delta_l = shade[0] - sample[0]
      delta_c = chroma.(shade) - chroma.(sample)
      delta_h_squared = [ (shade[1] - sample[1])**2 + (shade[2] - sample[2])**2 - delta_c**2, 0 ].max
      s_c = 1 + 0.045 * chroma.(shade)
      s_h = 1 + 0.015 * chroma.(shade)

      Math.sqrt(delta_l**2 + (delta_c / s_c)**2 + delta_h_squared / s_h**2)
    end

    def normalise(hex)
      "##{hex.to_s.delete_prefix('#').upcase}"
    end

    # sRGB hex -> [L, a, b], or nil when it isn't a colour.
    def lab(hex)
      match = HEX.match(hex.to_s.strip)
      return unless match

      linear = match.captures.map { |pair| linearise(pair.to_i(16) / 255.0) }
      xyz = [
        linear[0] * 0.4124 + linear[1] * 0.3576 + linear[2] * 0.1805,
        linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722,
        linear[0] * 0.0193 + linear[1] * 0.1192 + linear[2] * 0.9505
      ]
      fx, fy, fz = xyz.zip(D65).map { |value, white| pivot(value / white) }

      [ 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz) ]
    end

    def linearise(channel)
      channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end

    def pivot(ratio)
      ratio > 0.008856 ? Math.cbrt(ratio) : (7.787 * ratio) + (16.0 / 116)
    end
  end
end
