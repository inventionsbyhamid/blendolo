# "Make this my routine", and the routine as big step cards, one per screen.
class RoutinesController < ApplicationController
  include KitScoped

  before_action :open_example_routine, only: :create
  before_action :keep_example_kits_as_they_are, only: :create

  before_action :require_consent
  before_action :require_routine, only: %i[show step print]

  def show
    @steps = RoutinePlan.steps(@kit)
  end

  # Every card, one per printed page, in large print.
  def print
    @steps = RoutinePlan.steps(@kit)
  end

  # One step card: the step on the easy preview (or today's photo), zoomed to its part of the face.
  def step
    @steps = RoutinePlan.steps(@kit)
    @number = params[:n].to_i
    @step = @steps[@number - 1] if @number.positive?
    raise ActiveRecord::RecordNotFound, "No such step" unless @step

    @with = StepPreview.with(@kit)
    @photo = today_photo

    @entry = RoutinePlan.entries(@kit)[@number - 1]
  end

  # Choosing the same look again just sets the same routine.
  def create
    key = params[:look_key].to_s
    look_steps = key == "signature" ? signature_steps : LookForKit.find(@kit, key).easy_steps
    @kit.update!(chosen_look_key: key, routine: RoutinePlan.from(look_steps))
    redirect_to kit_routine_path(@kit)
  rescue KeyError
    raise ActiveRecord::RecordNotFound, "No such look"
  end

  private
    # An example person's routine follows their chosen look; choosing that look again just opens it.
    def open_example_routine
      redirect_to kit_routine_path(@kit) if @kit.example? && params[:look_key] == @kit.chosen_look_key
    end

    def require_routine
      redirect_to kit_looks_path(@kit) if RoutinePlan.entries(@kit).empty?
    end

    def signature_steps
      reference = @kit.photos.reference.order(:created_at).last
      signature = SignatureLook.build(@kit, reference, liner: params[:liner], lips: params[:lips]) or raise KeyError
      signature.easy_steps
    end
end
