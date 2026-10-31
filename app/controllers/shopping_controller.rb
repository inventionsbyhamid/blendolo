# The shopping list: product types for the routine with the ease tags that matter for these hands, what to avoid,
# and products from the demo catalogue for each step, easiest first for these hands.
class ShoppingController < ApplicationController
  include KitScoped

  def show
    @steps = RoutinePlan.steps(@kit)
    @profile = @kit.hand_profile
    @matters = ProductEase.tags_that_matter(@profile)
    @avoid = ProductEase.avoid(@profile)
  end
end
