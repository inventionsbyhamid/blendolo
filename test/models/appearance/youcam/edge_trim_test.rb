require "test_helper"

class Appearance::Youcam::EdgeTrimTest < ActiveSupport::TestCase
  test "a makeup result loses its dark top row" do
    # The top left corner of a makeup result as the provider sent it: its first row is near black.
    image = Appearance::Image.from_bytes(file_fixture("youcam/makeup/dark_top_row.jpg").binread)
    assert_operator row_brightness(image, 0), :<, 40

    trimmed = Appearance::Youcam::EdgeTrim.call(image)

    assert_equal [ "image/jpeg", "result.jpg" ], [ trimmed.content_type, trimmed.filename ]
    assert_equal [ 160, 118 ], size(trimmed), "two rows off the top, the left edge kept"
    assert_operator row_brightness(trimmed, 0), :>, 150
  end

  test "a dark left edge goes too" do
    grey = Vips::Image.black(40, 30).linear(1, 180).cast(:uchar)
    dark = grey.draw_rect(10, 0, 0, 1, 30, fill: true).draw_rect(10, 0, 0, 40, 1, fill: true)
    image = Appearance::Image.from_bytes(dark.bandjoin([ dark, dark ]).pngsave_buffer, basename: "look")

    trimmed = Appearance::Youcam::EdgeTrim.call(image)

    assert_equal [ "image/png", "look.png" ], [ trimmed.content_type, trimmed.filename ]
    assert_equal [ 39, 28 ], size(trimmed)
  end

  test "an image it can't read is stored as it came" do
    image = Appearance::Image.new(io: StringIO.new("\xFF\xD8\xFFnot really".b), filename: "result.jpg", content_type: "image/jpeg")
    assert_same image, Appearance::Youcam::EdgeTrim.call(image)
  end

  private
    def vips(image) = Vips::Image.new_from_buffer(image.bytes, "")

    def size(image) = vips(image).then { [ it.width, it.height ] }

    def row_brightness(image, y)
      vips(image).colourspace(:b_w).extract_band(0).then { it.crop(0, y, it.width, 1).avg }
    end
end
