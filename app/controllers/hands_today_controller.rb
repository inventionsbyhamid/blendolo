# "My hands today": steady, a bit shaky, or very shaky or stiff. Sets target sizes and the repeat-tap window.
class HandsTodayController < ApplicationController
  include KitScoped

  def update
    value = params[:hands_today].to_s
    @kit.update!(hands_today: value.to_i) if value.match?(/\A[0-2]\z/)
    redirect_to url_from(params[:return_to]) || url_from(request.referer) || kit_path(@kit)
  end
end
