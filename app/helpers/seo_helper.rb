# Search and sharing tags. A view calls seo(...) once; the layout prints them with seo_tags.
#
# A page that never calls seo is noindex: private pages (kits, shares) stay out of search even if a view forgets.
module SeoHelper
  SITE_URL = "https://blendolo.dijmo.com".freeze
  SITE_NAME = "Blendolo".freeze
  DEFAULT_TITLE = "Blendolo: makeup made easy for hands that shake".freeze
  DEFAULT_DESCRIPTION = "For people with Parkinson's, tremor or stiff hands. See your favourite look on your own " \
    "face, then do it in easy steps. Big buttons. Free.".freeze
  DEFAULT_IMAGE_ALT = "Blendolo: makeup made easy for hands that shake. A smiling woman at her kitchen table next " \
    "to a card that swaps liquid lipstick for a tinted balm.".freeze

  # social_description and x_description are the shorter lines for link previews (Open Graph and X); they default to
  # the description.
  def seo(title:, description:, image: nil, canonical: nil, noindex: false, social_description: nil, x_description: nil)
    @seo = { title:, description:, image:, canonical:, noindex:, social_description:, x_description: }
  end

  # A private page's own title (WCAG 2.4.2), without making it a search page: it stays noindex.
  def page_title(title)
    @page_title = title
  end

  def seo_title
    title = @seo&.dig(:title) || @page_title || content_for(:title)
    return DEFAULT_TITLE if title.blank?

    title.include?(SITE_NAME) ? title : "#{title} | #{SITE_NAME}"
  end

  def seo_noindex?
    @seo.nil? || @seo[:noindex]
  end

  def seo_tags
    description = @seo&.dig(:description) || DEFAULT_DESCRIPTION
    social = @seo&.dig(:social_description) || description
    x = @seo&.dig(:x_description) || social
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
      tag.meta(property: "og:description", content: social),
      tag.meta(property: "og:image", content: image),
      tag.meta(property: "og:image:width", content: "1200"),
      tag.meta(property: "og:image:height", content: "630"),
      tag.meta(property: "og:image:alt", content: DEFAULT_IMAGE_ALT),
      tag.meta(name: "twitter:card", content: "summary_large_image"),
      tag.meta(name: "twitter:title", content: title),
      tag.meta(name: "twitter:description", content: x),
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
