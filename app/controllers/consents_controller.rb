# What we keep and for how long, before any photo.
class ConsentsController < ApplicationController
  include KitScoped

  before_action :keep_example_kits_as_they_are, only: :create

  def show
  end

  def create
    retention_days = params[:retention_days].to_i.presence_in(Kit::RETENTION_DAYS) || 30
    @kit.update!(consented_at: @kit.consented_at || Time.current, retention_days:)
    redirect_to kit_hand_path(@kit, 1)
  end
end
