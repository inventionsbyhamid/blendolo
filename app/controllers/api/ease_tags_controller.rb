module Api
  # Ease tags for shops: GET /api/ease_tags?format=stick&closure=flip_cap returns a product's ease tags and its
  # ease for each hand profile. Answers 501 until the ease engine can score products.
  class EaseTagsController < ActionController::API
    def index
      render json: { error: "not_ready", message: "Ease tags for products are coming soon." }, status: :not_implemented
    end
  end
end
