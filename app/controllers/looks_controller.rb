# The looks, easiest first for these hands, and one look on today's photo: classic and easy side by side.
class LooksController < ApplicationController
  include KitScoped

  before_action :keep_example_kits_as_they_are, only: %i[previews tweak]
  before_action :require_consent
  before_action :require_today_photo, only: %i[show previews tweak]
  before_action :set_look, only: %i[show previews tweak]
  before_action :require_kit_owner, only: %i[previews tweak]
  rate_limit to: 10, within: 1.minute, only: :previews, name: "previews", with: -> { too_many_requests }
  rate_limit to: 10, within: 1.minute, only: :tweak, name: "tweak", with: -> { too_many_requests }

  def index
    @looks = LookForKit.easiest_first(@kit)
  end

  # Shows the renders that exist. Nothing is made here: the page asks for them with a POST (previews).
  def show
    @level = level_param
    # A preview refused for want of a sign in or credits shows as not made yet: the price below asks again.
    @classic = unpaid_as_nil(Previews.find(@kit, today_photo, @look.key, :classic, @look.classic_effects(today_photo)))
    @easy = unpaid_as_nil(Previews.find(@kit, today_photo, @look.key, :easy, @look.easy_effects(today_photo)))
    @tweak = unpaid_as_nil(Previews.find(@kit, today_photo, @look.key, :tweak, @look.easy_effects(today_photo, level: @level))) unless @level.zero?
    needed = (@level.zero? ? [ @classic, @easy ] : [ @classic, @easy, @tweak ]).count(nil)
    @waiting = needed.positive? && !@kit.example?
    # Shown before spending: "Uses 2 credits. You have 14."
    @cost = needed * Credits.cost(:makeup)
  end

  # "Show it on my face": makes the classic and easy renders (and the tweak at this level), once, paid with the
  # account's credits. Safe to repeat.
  def previews
    level = level_param
    return if short_of_credits?(unpaid_count(level) * Credits.cost(:makeup), kit_look_path(@kit, @look.key, level: (level unless level.zero?)))

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

    # The renders "Show it on my face" would pay for at this level: those not made yet, or refused for want of
    # credits or a sign in.
    def unpaid_count(level)
      wanted = [ [ :classic, @look.classic_effects(today_photo) ], [ :easy, @look.easy_effects(today_photo) ] ]
      wanted << [ :tweak, @look.easy_effects(today_photo, level:) ] unless level.zero?
      wanted.count { |kind, effects| unpaid_as_nil(Previews.find(@kit, today_photo, @look.key, kind, effects)).nil? }
    end

    def unpaid_as_nil(render)
      render unless render&.awaiting_payment?
    end

    def level_param
      params[:level].to_i.clamp(*LookForKit::LEVELS.keys.minmax)
    end
end
