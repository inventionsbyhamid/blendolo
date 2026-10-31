# Finds the kit from its private token (/k/:token). Unknown, deleted and expired kits are a plain 404: no hint that
# a kit was ever there. Every visit counts as activity, so retention runs from the last visit.
module KitScoped
  extend ActiveSupport::Concern
  include ExampleKitsReadOnly

  # Write the activity time at most this often, not on every request.
  TOUCH_EVERY = 1.minute

  included do
    before_action :skip_prefetch
    before_action :set_kit
  end

  private
    # Turbo prefetches links on hover. Kit pages are private and some start work, so a prefetch gets nothing.
    def skip_prefetch
      head :no_content if request.get? && request.headers["X-Sec-Purpose"] == "prefetch"
    end

    def set_kit
      @kit = Kit.find_by(token: params[:kit_token] || params[:token])
      raise ActiveRecord::RecordNotFound, "No such kit" unless @kit && @kit.purge_after.future?

      # Example kits are shared and never written to; they are rebuilt when they expire.
      @kit.touch_activity! if !@kit.example? && @kit.last_active_at.before?(TOUCH_EVERY.ago)
      remember_kit(@kit) unless @kit.example?
      response.set_header("X-Robots-Tag", "noindex, nofollow")
    end

    # Photos and previews need consent first.
    def require_consent
      redirect_to kit_consent_path(@kit) unless @kit.consented_at?
    end

    # Today's photo, the one previews go on.
    def today_photo
      @today_photo ||= @kit.photos.today.order(:created_at).last
    end

    def require_today_photo
      redirect_to new_kit_photo_path(@kit) unless today_photo
    end

    # Previews on a person's own face are paid with credits, so they need the account the kit is in. A kit in no
    # account joins the signed-in one here. Example kits stop before this (keep_example_kits_as_they_are).
    def require_kit_owner
      if !signed_in?
        redirect_to url_from(request.referer) || kit_path(@kit), notice: CreditsHelper::SIGN_IN
      elsif !current_user.claim!(@kit)
        redirect_to url_from(request.referer) || kit_path(@kit), notice: CreditsHelper::OTHER_ACCOUNT
      end
    end
end
