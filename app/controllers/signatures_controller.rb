# Bring back a signature look, one decision per screen: an old photo of you wearing it (photos/new?kind=reference),
# "Did you wear eyeliner?", "Lips?", then the old photo, today with the look put on by the provider (a transfer) and
# today with the easy version rebuilt from colours sampled on the old photo.
class SignaturesController < ApplicationController
  include KitScoped

  before_action :keep_example_kits_as_they_are, only: :create
  before_action :require_consent
  before_action :require_today_photo
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { too_many_requests }

  def show
    @reference = @kit.photos.reference.order(:created_at).last
    return show_example if @kit.example?

    @liner = params[:liner].presence_in(SignatureLook::LINERS.keys)
    @signature = SignatureLook.build(@kit, @reference, liner: @liner, lips: params[:lips])
    return unless @signature

    @transfer = Previews.for(@kit, today_photo, "signature", :transfer, [], reference_photo: @reference)
    @easy = Previews.for(@kit, today_photo, "signature", :easy, @signature.easy_effects(today_photo))
  end

  # The two answers for the old photo already chosen. Sending them twice finds the same renders.
  def create
    reference = @kit.photos.reference.order(:created_at).last
    signature = SignatureLook.build(@kit, reference, liner: params[:liner], lips: params[:lips])
    return redirect_to(kit_signature_path(@kit)) unless signature

    Previews.for(@kit, today_photo, "signature", :transfer, [], reference_photo: reference)
    Previews.for(@kit, today_photo, "signature", :easy, signature.easy_effects(today_photo))
    redirect_to kit_signature_path(@kit, liner: signature.liner, lips: signature.lips)
  end

  private
    # An example person's stored signature look: their transfer and its easy version.
    def show_example
      @transfer = Previews.for(@kit, today_photo, "signature", :transfer, [], reference_photo: @reference)
      @easy = Previews.for(@kit, today_photo, "signature", :easy, [])
    end
end
