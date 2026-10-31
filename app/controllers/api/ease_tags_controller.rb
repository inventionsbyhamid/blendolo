module Api
  # Ease tags for shops: GET /api/ease_tags?product_format=stick&closure=pull_cap&grip=chunky&step=tinted_balm answers
  # a product's ease tags and its ease for six hand profiles. Documented on /brands. Always JSON. (Not "format":
  # Rails reads that as the response format.)
  class EaseTagsController < ActionController::API
    rate_limit to: 60, within: 1.minute

    def index
      product = ProductEase.new(format: params[:product_format], closure: params[:closure], grip: params[:grip],
        step: params[:step])
      render json: product.as_api_json
    rescue ProductEase::Invalid => error
      render status: :unprocessable_content, json: {
        error: "invalid", message: error.message,
        allowed: { product_format: ProductEase::FORMATS, closure: ProductEase::CLOSURES.keys, grip: ProductEase::GRIPS,
                   step: Ease::StepCatalogue.ids }
      }
    end
  end
end
