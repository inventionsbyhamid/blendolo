# Pages for a signed-in account. Anyone else goes to the "Sign in with Google" page first and comes back afterwards:
# to the same page for a GET, or to sign_in_origin for a form (a POST can't be repeated after signing in).
module RequiresSignIn
  extend ActiveSupport::Concern

  included do
    before_action :require_sign_in
  end

  private
    def require_sign_in
      return if signed_in?

      redirect_to sign_in_path(origin: request.get? ? request.fullpath : sign_in_origin)
    end

    def sign_in_origin
      request.fullpath
    end

    def private_page
      response.set_header("X-Robots-Tag", "noindex, nofollow")
    end
end
