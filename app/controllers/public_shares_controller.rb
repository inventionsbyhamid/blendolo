# What someone with a share link sees: the routine, and photos only if the kit chose to share them. A revoked or
# expired link is our plain 404.
class PublicSharesController < ApplicationController
  def show
    @share = Share.find_by(token: params[:token])
    raise ActiveRecord::RecordNotFound, "No such share" unless @share&.live? && @share.kit.purge_after.future?

    # Not @kit: the layout would show the kit's own menu to the helper.
    @shared_kit = @share.kit
    @steps = RoutinePlan.steps(@shared_kit)
    @photos = @share.routine_and_photos?
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
end
