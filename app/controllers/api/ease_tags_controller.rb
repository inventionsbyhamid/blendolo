module Api
  # Ease tags for shops: GET /api/ease_tags?format=stick&closure=pull_cap&grip=chunky&step=tinted_balm answers a
  # product's ease tags and its ease for six hand profiles. Documented on /brands. The product's format is read
  # from the query string; the response is always JSON.
  class EaseTagsController < ActionController::API
    rate_limit to: 60, within: 1.minute

    def index
      query = request.query_parameters
      product = ProductEase.new(format: query["format"], closure: query["closure"], grip: query["grip"], step: query["step"])
      render json: product.as_api_json
    rescue ProductEase::Invalid => error
      render status: :unprocessable_content, json: {
        error: "invalid", message: error.message,
        allowed: { format: ProductEase::FORMATS, closure: ProductEase::CLOSURES.keys, grip: ProductEase::GRIPS }
      }
    end
  end
end
