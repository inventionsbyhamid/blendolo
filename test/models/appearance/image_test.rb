require "test_helper"

class Appearance::ImageTest < ActiveSupport::TestCase
  test "detects png and jpeg by their bytes, not their names" do
    png = Appearance::Image.from_bytes(file_fixture("youcam/makeup/m01_full_look.png").binread)
    assert_equal [ "image/png", "result.png" ], [ png.content_type, png.filename ]

    jpeg = Appearance::Image.from_bytes(file_fixture("youcam/makeup/m03_mu_transfer.jpg").binread, basename: "transfer")
    assert_equal [ "image/jpeg", "transfer.jpg" ], [ jpeg.content_type, jpeg.filename ]

    assert_raises(Appearance::Error) { Appearance::Image.from_bytes("<html>expired</html>") }
  end

  test "reads its bytes more than once" do
    image = Appearance::Image.new(io: StringIO.new("abc"), filename: "a.jpg", content_type: "image/jpeg")
    assert_equal "abc", image.bytes
    assert_equal "abc", image.bytes
  end
end
