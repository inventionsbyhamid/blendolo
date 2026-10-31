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
    if kit&.example?
      @kit = kit
      return keep_example_kits_as_they_are
    end

    # A kit in an account is the account's: only its owner, signed in, deletes it (a kit link alone isn't enough).
    if kit&.user_id && !kit.owned_by?(current_user)
      return redirect_to(kit_path(kit), notice: "This kit is in an account. Sign in with that account to delete it.")
    end

    kit&.destroy_everything!
    forget_kit
    redirect_to root_path, notice: "Everything is deleted. Our photo partner deletes its copies within 30 days."
  end
end
