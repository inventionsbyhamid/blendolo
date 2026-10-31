# Example people: Rosa, June and Amara. Each visitor gets their own copy of the example kit, with stored previews.
class ExamplesController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :start, with: -> { too_many_requests }

  def index
  end

  def show
    @key = params[:key]
    @template = ExampleKit.template(@key)
  end

  def start
    kit = ExampleKit.start!(params[:key])
    if kit
      remember_kit(kit)
      redirect_to kit_path(kit)
    else
      redirect_to example_path(params[:key])
    end
  end
end
