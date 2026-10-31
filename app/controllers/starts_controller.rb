# Start: pick a path (for me, or for someone I help) and get a private kit. No account needed; a signed-in person's
# kit goes straight into their account.
class StartsController < ApplicationController
  PATHS = %w[self_use helper].freeze
  # A second "Start" within this time from the same device carries on with the kit the first one made.
  REPEAT_WINDOW = 30.seconds

  rate_limit to: 10, within: 1.minute, only: :create, with: -> { too_many_requests }

  def show
    @remembered_kit = remembered_kit
    @remembered_kit = nil unless @remembered_kit&.purge_after&.future?
  end

  def create
    path = params[:path].presence_in(PATHS) or return redirect_to(start_path)
    kit = repeat_of(path) || Kit.create!(path:, user: current_user)
    remember_kit(kit)
    redirect_to kit_consent_path(kit)
  end

  private
    def repeat_of(path)
      kit = remembered_kit
      kit if kit&.path == path && kit.consented_at.nil? && kit.created_at.after?(REPEAT_WINDOW.ago)
    end
end
