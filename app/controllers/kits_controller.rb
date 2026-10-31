# Kit home, and "Delete everything" (a confirm page, then delete at once).
class KitsController < ApplicationController
  include KitScoped
  skip_before_action :set_kit, only: :destroy

  def show
  end

  def delete
  end

  # Safe to send twice: a kit that's already gone ends on the same "deleted" page.
  def destroy
    kit = Kit.find_by(token: params[:token])
    kit&.destroy_everything!
    forget_kit
    redirect_to root_path, notice: "Everything is deleted. Our photo partner deletes its copies within 30 days."
  end
end
