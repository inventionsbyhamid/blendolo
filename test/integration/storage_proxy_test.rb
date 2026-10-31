require "test_helper"
require "support/kit_helpers"

# Photos and previews come from our own origin, through Active Storage's proxy, never from the bucket directly.
class StorageProxyTest < ActionDispatch::IntegrationTest
  include KitHelpers

  test "a render's image url is same origin" do
    kit = make_kit(tremor: 2)
    post previews_kit_look_path(kit, "red_lip")
    render = kit.renders.classic.sole
    render.result.attach(io: file_fixture("face.jpg").open, filename: "classic.jpg", content_type: "image/jpeg")
    render.update!(status: :done)

    get kit_look_path(kit, "red_lip")
    src = css_select("##{ActionView::RecordIdentifier.dom_id(render)} img").first["src"]
    assert_match %r{\A/rails/active_storage/representations/proxy/}, src

    get src
    assert_response :success
    assert_equal "image/webp", response.media_type
    assert_equal "max-age=3600, private", response.headers["Cache-Control"]
  end

  test "a photo through the proxy is private and kept for an hour at most" do
    kit = make_kit
    get rails_storage_proxy_path(kit.photos.sole.image)

    assert_response :success
    assert_equal "max-age=3600, private", response.headers["Cache-Control"]
  end
end
