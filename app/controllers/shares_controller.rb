# Share links for a helper, family or an occupational therapist: scoped, expiring, revocable.
class SharesController < ApplicationController
  include KitScoped

  # A second tap within this time gives back the link the first tap made.
  REPEAT_WINDOW = 30.seconds

  rate_limit to: 10, within: 1.minute, only: :create, with: -> { too_many_requests }

  def index
    @shares = @kit.shares.live.order(created_at: :desc)
  end

  def create
    audience = params[:audience].presence_in(Share.audiences.keys) || "helper"
    scope = params[:scope].presence_in(Share.scopes.keys) || "routine_only"
    share = @kit.shares.live.where(audience:, scope:).where(created_at: REPEAT_WINDOW.ago..).first ||
      @kit.shares.create!(audience:, scope:)
    redirect_to kit_shares_path(@kit, made: share.token)
  end

  # Switching a link off twice is the same as once.
  def destroy
    share = @kit.shares.find_by!(token: params[:share_token])
    share.revoke! unless share.revoked_at?
    redirect_to kit_shares_path(@kit), notice: "That link is switched off."
  end
end
