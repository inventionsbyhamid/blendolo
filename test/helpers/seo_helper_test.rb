require "test_helper"

class SeoHelperTest < ActionView::TestCase
  setup { controller.request.path = "/k/abc" }

  test "a page that never calls seo is noindex and has no canonical link" do
    tags = seo_tags

    assert_includes tags, '<meta name="robots" content="noindex, nofollow">'
    assert_not_includes tags, "canonical"
    assert_equal "Blendolo: makeup made easy for hands that shake", seo_title
  end

  test "seo with noindex keeps the page out of search" do
    seo title: "Your kit", description: "Private", noindex: true

    assert_includes seo_tags, "noindex"
    assert_equal "Your kit | Blendolo", seo_title
  end

  test "an indexable page gets its canonical url on the site's domain" do
    controller.request.path = "/privacy"
    seo title: "Privacy", description: "What we keep"

    assert_includes seo_tags, '<link rel="canonical" href="https://blendolo.dijmo.com/privacy">'
    assert_not_includes seo_tags, "noindex"
    assert_not_includes seo_tags, "ld+json"
  end
end
