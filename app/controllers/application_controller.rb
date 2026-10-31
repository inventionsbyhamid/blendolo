class ApplicationController < ActionController::Base
  # Browsers that run Tailwind 4, import maps and ES modules: Safari 16.4 (iOS 16.4) and up. Older iPhones and iPads
  # are common among the people Blendolo is for, so this is as wide as the front end allows.
  allow_browser versions: { safari: 16.4, chrome: 111, firefox: 128, opera: 97, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  KIT_COOKIE = :blendolo_kit

  helper_method :current_user, :signed_in?

  private
    # The signed-in account, from the user id in the session (Rails' session cookie: encrypted, signed, httponly).
    def current_user
      return @current_user if defined?(@current_user)

      @current_user = (User.find_by(id: session[:user_id]) if session[:user_id])
    end

    def signed_in?
      current_user.present?
    end

    # A fresh session (a session id from before signing in is never reused) holding only the user's id.
    def sign_in(user)
      reset_session
      session[:user_id] = user.id
      @current_user = user
    end

    # Signing out also forgets this device's kit: it may be in the account.
    def sign_out
      reset_session
      forget_kit
      @current_user = nil
    end

    # The kit this device last used, so "Start" can offer to carry on with it.
    def remembered_kit
      token = cookies.signed[KIT_COOKIE]
      Kit.find_by(token:) if token.present?
    end

    def remember_kit(kit)
      cookies.signed[KIT_COOKIE] = { value: kit.token, expires: kit.purge_after, httponly: true, same_site: :lax }
    end

    def forget_kit
      cookies.delete(KIT_COOKIE)
    end

    # Answer for rate_limit: a page that says to wait, never a bare error.
    def too_many_requests
      render "shared/slow_down", status: :too_many_requests
    end
end
