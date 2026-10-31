require "test_helper"

class Looks::ColourSamplerMappingTest < ActiveSupport::TestCase
  def test_an_exact_shade_maps_to_itself
    Looks::ColourSamplerMapping::SHADES.each do |region, shades|
      shades.each_value { assert_equal it, Looks::ColourSamplerMapping.nearest(region, it) }
    end
  end

  def test_muted_samples_snap_to_the_nearest_shade
    assert_equal "#B0182A", Looks::ColourSamplerMapping.nearest(:lips, "#A52030"), "red"
    assert_equal "#8E1F2F", Looks::ColourSamplerMapping.nearest(:lips, "#7A2433"), "berry"
    assert_equal "#B5776B", Looks::ColourSamplerMapping.nearest(:lips, "#B08070"), "nude"
    assert_equal "#2F3A5A", Looks::ColourSamplerMapping.nearest(:lids, "#283050"), "navy"
    assert_equal "#E59A7A", Looks::ColourSamplerMapping.nearest(:cheeks, "#E0A080"), "peach"
  end

  def test_a_red_lip_faded_by_an_old_print_still_snaps_to_red
    assert_equal "#B0182A", Looks::ColourSamplerMapping.nearest(:lips, "#9A4E43")
    assert_equal "#7A3E33", Looks::ColourSamplerMapping.nearest(:lips, "#7A4036"), "a real brown stays brown"
  end

  def test_unusable_colours_come_back_nil
    assert_nil Looks::ColourSamplerMapping.nearest(:lips, nil)
    assert_nil Looks::ColourSamplerMapping.nearest(:lips, "red")
    assert_nil Looks::ColourSamplerMapping.nearest(:lips, "#12345")
  end

  def test_map_reads_string_or_symbol_keys_and_keeps_skin_as_sampled
    mapped = Looks::ColourSamplerMapping.map("lips" => "#a52030", cheeks: "#E0A080", "skin" => "c08a6a")

    assert_equal({ lips: "#B0182A", lids: nil, cheeks: "#E59A7A", skin: "#C08A6A" }, mapped)
    assert_equal({ lips: nil, lids: nil, cheeks: nil, skin: nil }, Looks::ColourSamplerMapping.map(nil))
  end

  def test_lab_matches_known_values
    white = Looks::ColourSamplerMapping.lab("#FFFFFF")
    red = Looks::ColourSamplerMapping.lab("#FF0000")

    assert_in_delta 100.0, white[0], 0.01
    assert_in_delta 0.0, white[1], 0.01
    assert_in_delta 53.24, red[0], 0.05
    assert_in_delta 80.09, red[1], 0.05
    assert_in_delta 67.20, red[2], 0.05
  end
end
