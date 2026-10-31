# "My hands today": steady, a bit shaky, or very shaky or stiff. Sets target sizes and the repeat-tap window.
class HandsTodayController < ApplicationController
  include KitScoped

  # On an example person's kit it is kept for this visitor only (the kit is shared).
  def update
    value = params[:hands_today].to_s
    if !value.match?(/\A[0-2]\z/)
      # Not a choice we offer: change nothing.
    elsif @kit.example?
      session[:example_hands_today] = value.to_i
    else
      @kit.update!(hands_today: value.to_i)
    end
    redirect_to url_from(params[:return_to]) || url_from(request.referer) || kit_path(@kit)
  end
end
