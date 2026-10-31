# Search and sharing tags. A view calls seo(...) once; the layout prints them with seo_tags.
#
# A page that never calls seo is noindex: private pages (kits, shares) stay out of search even if a view forgets.
module SeoHelper
  SITE_URL = "https://blendolo.dijmo.com".freeze
  SITE_NAME = "Blendolo".freeze
  DEFAULT_TITLE = "Blendolo: your favourite makeup look, in easier steps".freeze
  DEFAULT_DESCRIPTION = "See your favourite look on your own photo, then get it with steps made for hands that " \
    "shake, tire or hurt. Big buttons. Works with Voice Control. Free.".freeze
  DEFAULT_IMAGE_ALT = "Blendolo: the same red lip, in easier steps. A smiling woman at her kitchen table next to a " \
    "card that swaps liquid lipstick for a tinted balm.".freeze

  def seo(title:, description:, image: nil, canonical: nil, noindex: false)
    @seo = { title:, description:, image:, canonical:, noindex: }
  end

  def seo_title
    title = @seo&.dig(:title) || content_for(:title)
    return DEFAULT_TITLE if title.blank?

    title.include?(SITE_NAME) ? title : "#{title} | #{SITE_NAME}"
  end

  def seo_noindex?
    @seo.nil? || @seo[:noindex]
  end

  def seo_tags
    description = @seo&.dig(:description) || DEFAULT_DESCRIPTION
    image = absolute_url(@seo&.dig(:image) || image_path("og.png"))
    title = seo_title

    tags = [ tag.meta(name: "description", content: description) ]
    if seo_noindex?
      tags << tag.meta(name: "robots", content: "noindex, nofollow")
    else
      tags << tag.link(rel: "canonical", href: canonical_url)
    end
    tags += [
      tag.meta(property: "og:type", content: "website"),
      tag.meta(property: "og:site_name", content: SITE_NAME),
      tag.meta(property: "og:locale", content: "en_GB"),
      tag.meta(property: "og:title", content: title),
      tag.meta(property: "og:description", content: description),
      tag.meta(property: "og:image", content: image),
      tag.meta(property: "og:image:width", content: "1200"),
      tag.meta(property: "og:image:height", content: "630"),
      tag.meta(property: "og:image:alt", content: DEFAULT_IMAGE_ALT),
      tag.meta(name: "twitter:card", content: "summary_large_image"),
      tag.meta(name: "twitter:title", content: title),
      tag.meta(name: "twitter:description", content: description),
      tag.meta(name: "twitter:image", content: image),
      tag.meta(name: "twitter:image:alt", content: DEFAULT_IMAGE_ALT)
    ]
    tags << tag.meta(property: "og:url", content: canonical_url) unless seo_noindex?
    tags << home_json_ld if request.path == "/"
    safe_join(tags, "\n    ")
  end

  private
    def canonical_url
      absolute_url(@seo&.dig(:canonical) || request.path)
    end

    def absolute_url(path)
      path.to_s.start_with?("http") ? path : "#{SITE_URL}#{path}"
    end

    # Organization and WebApplication, on the home page only.
    def home_json_ld
      graph = {
        "@context" => "https://schema.org",
        "@graph" => [
          { "@type" => "Organization", "@id" => "#{SITE_URL}/#org", "name" => SITE_NAME, "url" => "#{SITE_URL}/",
            "logo" => "#{SITE_URL}/icon-512.png" },
          { "@type" => "WebApplication", "@id" => "#{SITE_URL}/#app", "name" => SITE_NAME, "url" => "#{SITE_URL}/",
            "applicationCategory" => "LifestyleApplication", "operatingSystem" => "Any (web browser)",
            "inLanguage" => "en", "offers" => { "@type" => "Offer", "price" => "0", "priceCurrency" => "USD" },
            "description" => "Makeup help for hands that shake, tire or hurt. See a look on your own photo, get an " \
              "ease score for your hands, swap hard steps for easy ones and follow big step cards read aloud.",
            "accessibilityFeature" => %w[largePrint readingOrder structuralNavigation alternativeText],
            "accessibilityControl" => %w[fullTouchControl fullKeyboardControl fullVoiceControl],
            "publisher" => { "@id" => "#{SITE_URL}/#org" } }
        ]
      }
      tag.script(graph.to_json.html_safe, type: "application/ld+json")
    end
end
