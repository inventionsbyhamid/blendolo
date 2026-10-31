# The five "Your hands" questions, one per screen, three answers each.
class HandsController < ApplicationController
  include KitScoped

  QUESTIONS = Kit::HAND_QUESTIONS

  before_action :set_question

  def show
  end

  # Answering again is harmless: it just sets the same answer.
  def update
    answer = params[:answer].to_s
    unless answer.match?(/\A[0-2]\z/)
      redirect_to kit_hand_path(@kit, @number)
      return
    end

    @kit.update!(@question => answer.to_i)
    redirect_to next_path
  end

  private
    def set_question
      @number = params[:question].to_i
      @question = QUESTIONS.fetch(@number - 1)
    end

    def next_path
      if @number < QUESTIONS.size
        kit_hand_path(@kit, @number + 1)
      elsif @kit.photos.today.exists?
        kit_looks_path(@kit)
      else
        new_kit_photo_path(@kit)
      end
    end
end
