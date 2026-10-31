# "Try again" on a preview that failed on our side (took too long, provider error, too busy) or was paused by the
# unit limits. Asking again goes through Render#request! like the first time: the cache, the unit guard and the jobs,
# so a pause that still holds fails again at no cost. Safe to tap twice: a render that is already on its way again
# isn't asked twice.
class RendersController < ApplicationController
  include KitScoped

  before_action :keep_example_kits_as_they_are
  rate_limit to: 10, within: 1.minute, with: -> { too_many_requests }

  def try_again
    preview = @kit.renders.find(params[:id])
    preview.request! if preview.failed? && RendersHelper::TRY_AGAIN.include?(preview.failure_reason)
    redirect_to url_from(request.referer) || kit_looks_path(@kit)
  end
end
