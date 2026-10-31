# The public pages: the landing page, pricing, terms, refunds, privacy, accessibility, sources, guides and the sitemap.
class PagesController < ApplicationController
  GUIDES = {
    "makeup-with-parkinsons" => {
      title: "Makeup with Parkinson's: what helps",
      description: "Do the detailed steps first while your hands are fresh, rest your elbow, and pick creams and " \
        "sticks that blend away wobbles. Tips from Parkinson's UK and people with Parkinson's."
    },
    "eyeliner-with-a-tremor" => {
      title: "How to wear eyeliner with a tremor",
      description: "Short strokes, a chunky pencil smudged along the lashes, or shadow pressed on with a flat " \
        "brush. Easier ways to wear eyeliner when your hands shake."
    },
    "makeup-with-arthritis-in-your-hands" => {
      title: "Makeup with arthritis in your hands",
      description: "Pumps instead of tubes, sponges instead of thin brushes, caps that open without a pinch. " \
        "Makeup tips for hands with arthritis, with sources."
    }
  }.freeze

  def home
  end

  def privacy
  end

  def pricing
  end

  def terms
  end

  def refunds
  end

  def accessibility
  end

  def sources
  end

  def guides
  end

  # For brands and shops: the ease tags API, with a live example.
  def brands
    @example_query = { product_format: "stick", closure: "pull_cap", grip: "chunky", step: "tinted_balm" }
    @example = ProductEase.new(format: "stick", closure: "pull_cap", grip: "chunky", step: "tinted_balm").as_api_json
  end

  def guide
    slug, @guide = GUIDES.find { |key, _| key == params[:slug] }
    raise ActionController::RoutingError, "No such guide" unless slug

    # The template comes from the list above, never from the request.
    render "pages/guides/#{slug.underscore}"
  end

  def sitemap
    @paths = [ root_path, guides_path, *GUIDES.keys.map { |slug| guide_path(slug) }, brands_path, pricing_path,
      privacy_path, terms_path, refunds_path, accessibility_path, sources_path ]
  end
end
