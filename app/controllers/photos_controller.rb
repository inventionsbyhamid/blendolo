# Today's photo (what previews go on) and the old photo for a signature look.
class PhotosController < ApplicationController
  include KitScoped

  before_action :require_consent
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { too_many_requests }

  def new
    @kind = params[:kind].presence_in(Photo.kinds.keys) || "today"
  end

  def create
    @upload = PhotoUpload.new(kit: @kit, file: params[:image], kind: params[:kind].presence || "today",
      sampled: params[:sampled], source: params[:source])

    if @kit.example?
      redirect_to kit_looks_path(@kit), notice: "Example people keep their own photo. Start your own kit to use yours."
    elsif @upload.save
      redirect_to @upload.photo.reference? ? kit_signature_path(@kit) : kit_looks_path(@kit)
    else
      @kind = @upload.kind.presence_in(Photo.kinds.keys) || "today"
      render :new, status: :unprocessable_content
    end
  end
end
