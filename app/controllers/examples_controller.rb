# Example people: Rosa, June and Amara. Their kits are shared and read-only, with stored previews: no photo of the
# visitor and no provider call.
class ExamplesController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :start, with: -> { too_many_requests }

  def index
    @people = Examples.all
  end

  def show
    @person = Examples.fetch(params[:key])
  end

  # Opens the example person's kit, building it from the stored photos and previews when it isn't there yet.
  def start
    kit = Examples.kit_for(params[:key])
    redirect_to kit_path(kit)
  rescue Errno::ENOENT, ActiveRecord::RecordInvalid => error
    Rails.logger.warn("Example #{params[:key]} isn't ready: #{error.message}")
    redirect_to example_path(params[:key], soon: 1)
  end
end
