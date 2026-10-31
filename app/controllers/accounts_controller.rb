# Your account: name and email from Google, credits, your kits, sign out, and "Delete my account" (a confirm page,
# then everything goes at once).
class AccountsController < ApplicationController
  before_action :require_sign_in, except: :destroy
  rate_limit to: 5, within: 1.minute, only: :destroy, with: -> { too_many_requests }

  def show
    @credits = Credits.balance(current_user)
    @kits = current_user.live_kits
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  def delete
  end

  # Safe to send twice: the second finds no account and ends on the same page.
  def destroy
    current_user&.destroy_everything!
    sign_out
    redirect_to root_path,
      notice: "Your account is deleted, with its kits, photos and credits. Our photo partner deletes its copies within 30 days."
  end

  private
    def require_sign_in
      redirect_to sign_in_path(origin: request.fullpath) unless signed_in?
    end
end
