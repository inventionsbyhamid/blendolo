# The shopping list: product types for your routine, with ease tags for your hands.
class ShoppingController < ApplicationController
  include KitScoped

  def show
    @steps = @kit.routine.present? ? RoutinePlan.steps(@kit) : []
  end
end
