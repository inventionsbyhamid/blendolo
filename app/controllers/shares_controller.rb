# Share links for a helper, family or an occupational therapist: scoped, expiring, revocable.
class SharesController < ApplicationController
  include KitScoped

  before_action :keep_example_kits_as_they_are, only: %i[create destroy restore]

  # A second tap within this time gives back the link the first tap made.
  REPEAT_WINDOW = 30.seconds
  # "Undo" after switching a link off works for this long.
  UNDO_WINDOW = 10.minutes

  rate_limit to: 10, within: 1.minute, only: :create, with: -> { too_many_requests }

  # The new link (or the one just switched off, for Undo) comes through the flash, never the address, so its token
  # stays out of logs.
  def index
    @shares = @kit.shares.live.order(created_at: :desc)
    @made = @shares.find { |share| share.token == flash[:made_share] } if flash[:made_share]
    @switched_off = @kit.shares.find_by(token: flash[:switched_off_share]) if flash[:switched_off_share]
  end

  # Repeat taps, even at the same moment, give back one link.
  def create
    audience = params[:audience].presence_in(Share.audiences.keys) || "helper"
    scope = params[:scope].presence_in(Share.scopes.keys) || "routine_only"
    share = @kit.with_lock do
      @kit.shares.live.where(audience:, scope:).where(created_at: REPEAT_WINDOW.ago..).first ||
        @kit.shares.create!(audience:, scope:)
    end
    redirect_to kit_shares_path(@kit), flash: { made_share: share.token }
  end

  # Switching a link off twice is the same as once. Undo stays on the next page until the next action.
  def destroy
    share = @kit.shares.find_by!(token: params[:share_token])
    share.revoke! unless share.revoked_at?
    redirect_to kit_shares_path(@kit), flash: { switched_off_share: share.token }
  end

  # Undo: the link works again, if it was switched off in the last few minutes and hasn't expired.
  def restore
    share = @kit.shares.find_by!(token: params[:share_token])
    if share.revoked_at&.after?(UNDO_WINDOW.ago) && share.expires_at.future?
      share.update!(revoked_at: nil)
      redirect_to kit_shares_path(@kit), notice: "That link works again."
    else
      redirect_to kit_shares_path(@kit), notice: "That link can't be switched back on. You can make a new one."
    end
  end
end
