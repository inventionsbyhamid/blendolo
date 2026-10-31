require "test_helper"
require "support/kit_helpers"

class RendersHelperTest < ActionView::TestCase
  include KitHelpers

  setup { @image = make_kit.photos.sole.image }

  test "pictures are resized WebP copies" do
    variant = ProxiedImage.variant(@image, 900).processed

    assert_equal "image/webp", variant.image.blob.content_type
  end

  test "an image link stays the same for ten minutes, so the browser can reuse the picture" do
    first = travel_to(Time.utc(2026, 11, 1, 12, 0, 1)) { proxied_image_path(@image, 900) }
    later = travel_to(Time.utc(2026, 11, 1, 12, 9, 59)) { proxied_image_path(@image, 900) }
    next_step = travel_to(Time.utc(2026, 11, 1, 12, 10, 0)) { proxied_image_path(@image, 900) }

    assert_equal first, later
    assert_not_equal first, next_step
  end

  test "an image link works for an hour at most" do
    made_at = Time.utc(2026, 11, 1, 12, 9, 59)
    path = travel_to(made_at) { proxied_image_path(@image, 900) }
    signed_id = Rails.application.routes.recognize_path(path)[:signed_blob_id]

    travel_to(made_at + 50.minutes) { assert_equal @image.blob, ActiveStorage::Blob.find_signed(signed_id) }
    travel_to(made_at + 51.minutes) { assert_nil ActiveStorage::Blob.find_signed(signed_id) }
  end
end
