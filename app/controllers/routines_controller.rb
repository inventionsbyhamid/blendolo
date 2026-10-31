# "Make this my routine", and the routine as big step cards, one per screen.
class RoutinesController < ApplicationController
  include KitScoped

  before_action :require_consent
  before_action :require_routine, only: %i[show step]

  def show
    @steps = RoutinePlan.steps(@kit)
  end

  def step
    @steps = RoutinePlan.steps(@kit)
    @number = params[:n].to_i
    @step = @steps[@number - 1] if @number.positive?
    raise ActiveRecord::RecordNotFound, "No such step" unless @step

    @entry = @kit.routine[@number - 1]
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
    def require_routine
      redirect_to kit_looks_path(@kit) if @kit.routine.blank?
    end

    def signature_steps
      reference = @kit.photos.reference.order(:created_at).last or raise KeyError
      steps = Looks::EffectsBuilder.signature(sampled: reference.sampled, liner: params[:liner], lips: params[:lips])
      Looks::Look.easy_steps(steps, @kit.hand_profile)
    rescue ArgumentError
      raise KeyError
    end
end
