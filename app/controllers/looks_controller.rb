# The looks, easiest first for these hands, and one look on today's photo: classic and easy side by side.
class LooksController < ApplicationController
  include KitScoped

  before_action :require_consent
  before_action :require_today_photo, only: %i[show tweak]
  before_action :set_look, only: %i[show tweak]
  rate_limit to: 10, within: 1.minute, only: %i[show tweak], with: -> { too_many_requests }

  def index
    @looks = LookForKit.easiest_first(@kit)
  end

  # The first view makes the classic and the easy render; later views (and double taps) find the same ones.
  def show
    @level = level_param
    @classic = Previews.for(@kit, today_photo, @look.key, :classic, @look.classic_effects(today_photo))
    @easy = Previews.for(@kit, today_photo, @look.key, :easy, @look.easy_effects(today_photo))
    @tweak = Previews.for(@kit, today_photo, @look.key, :tweak, @look.easy_effects(today_photo, level: @level)) unless @level.zero?
  end

  # "Softer" or "Bolder" on the easy version: one level at a time, five levels in all.
  def tweak
    change = { "softer" => -1, "bolder" => 1 }.fetch(params[:direction].to_s, 0)
    level = (level_param + change).clamp(*LookForKit::LEVELS.keys.minmax)
    Previews.for(@kit, today_photo, @look.key, :tweak, @look.easy_effects(today_photo, level:)) unless level.zero?
    redirect_to kit_look_path(@kit, @look.key, level: (level unless level.zero?))
  end

  private
    def set_look
      @look = LookForKit.find(@kit, params[:key])
    rescue KeyError
      raise ActiveRecord::RecordNotFound, "No such look"
    end

    def level_param
      params[:level].to_i.clamp(*LookForKit::LEVELS.keys.minmax)
    end
end
