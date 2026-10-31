class ApplicationController < ActionController::Base
  # Browsers that run Tailwind 4, import maps and ES modules: Safari 16.4 (iOS 16.4) and up. Older iPhones and iPads
  # are common among the people Blendolo is for, so this is as wide as the front end allows.
  allow_browser versions: { safari: 16.4, chrome: 111, firefox: 128, opera: 97, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  KIT_COOKIE = :blendolo_kit

  private
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
