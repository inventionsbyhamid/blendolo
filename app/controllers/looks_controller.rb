# The looks, easiest first for these hands, and one look on today's photo: classic and easy side by side.
class LooksController < ApplicationController
  include KitScoped

  before_action :keep_example_kits_as_they_are, only: %i[previews tweak]
  before_action :require_consent
  before_action :require_today_photo, only: %i[show previews tweak]
  before_action :set_look, only: %i[show previews tweak]
  rate_limit to: 10, within: 1.minute, only: :previews, name: "previews", with: -> { too_many_requests }
  rate_limit to: 10, within: 1.minute, only: :tweak, name: "tweak", with: -> { too_many_requests }

  def index
    @looks = LookForKit.easiest_first(@kit)
  end

  # Shows the renders that exist. Nothing is made here: the page asks for them with a POST (previews).
  def show
    @level = level_param
    @classic = Previews.find(@kit, today_photo, @look.key, :classic, @look.classic_effects(today_photo))
    @easy = Previews.find(@kit, today_photo, @look.key, :easy, @look.easy_effects(today_photo))
    @tweak = Previews.find(@kit, today_photo, @look.key, :tweak, @look.easy_effects(today_photo, level: @level)) unless @level.zero?
    needed = @level.zero? ? [ @classic, @easy ] : [ @classic, @easy, @tweak ]
    @waiting = needed.include?(nil) && !@kit.example?
  end

  # "Show it on my face": makes the classic and easy renders (and the tweak at this level), once. Safe to repeat.
  def previews
    level = level_param
    Previews.for(@kit, today_photo, @look.key, :classic, @look.classic_effects(today_photo))
    Previews.for(@kit, today_photo, @look.key, :easy, @look.easy_effects(today_photo))
    Previews.for(@kit, today_photo, @look.key, :tweak, @look.easy_effects(today_photo, level:)) unless level.zero?
    redirect_to kit_look_path(@kit, @look.key, level: (level unless level.zero?))
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
