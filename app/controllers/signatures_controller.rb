# Bring back a signature look: an old photo of you wearing it goes on today's photo (a transfer), and is rebuilt from
# easy steps using colours sampled from the old photo and two answers (liner, lips).
class SignaturesController < ApplicationController
  include KitScoped

  LINERS = %w[winged thin smudged none].freeze
  LIPS = %w[matte shiny sheer].freeze

  before_action :require_consent
  before_action :require_today_photo
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { too_many_requests }

  def show
    @reference = @kit.photos.reference.order(:created_at).last
    @liner = params[:liner].presence_in(LINERS)
    @lips = params[:lips].presence_in(LIPS)
    return unless @reference && @liner && @lips

    @transfer = Previews.for(@kit, today_photo, "signature", :transfer, [], reference_photo: @reference)
    @easy = Previews.for(@kit, today_photo, "signature", :easy, easy_effects)
  end

  # The old photo (or the one already sent) and the two answers. Sending it twice finds the same photo and renders.
  def create
    @liner = params[:liner].presence_in(LINERS)
    @lips = params[:lips].presence_in(LIPS)
    @reference = reference_from_params
    return if performed?
    return redirect_to(kit_signature_path(@kit), notice: "Please choose an old photo of you.") unless @reference
    return redirect_to(kit_signature_path(@kit), notice: "Please answer both questions.") unless @liner && @lips

    Previews.for(@kit, today_photo, "signature", :transfer, [], reference_photo: @reference)
    Previews.for(@kit, today_photo, "signature", :easy, easy_effects)
    redirect_to kit_signature_path(@kit, liner: @liner, lips: @lips)
  end

  private
    # A new upload, or the old photo already sent. Example people keep their own old photo.
    def reference_from_params
      return @kit.photos.reference.order(:created_at).last if params[:image].blank? || @kit.example?

      @upload = PhotoUpload.new(kit: @kit, file: params[:image], kind: "reference", sampled: params[:sampled])
      return @upload.photo if @upload.save

      render :show, status: :unprocessable_content
      nil
    end

    def easy_effects
      steps = Looks::EffectsBuilder.signature(sampled: @reference.sampled, liner: @liner, lips: @lips)
      Looks::EffectsBuilder.build(Looks::Look.easy_steps(steps, @kit.hand_profile), skin: today_photo.sampled["skin"])
    end
end
