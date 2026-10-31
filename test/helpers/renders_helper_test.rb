require "test_helper"
require "support/kit_helpers"

class RendersHelperTest < ActionView::TestCase
  include KitHelpers

  setup { @image = make_kit.photos.sole.image }

  test "pictures are resized WebP copies" do
    variant = ProxiedImage.variant(@image, 900).processed

    assert_equal "image/webp", variant.image.blob.content_type
  end
end
