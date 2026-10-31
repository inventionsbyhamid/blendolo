require "test_helper"

class RenderTest < ActiveSupport::TestCase
  setup do
    @kit = Kit.create!
    @today = @kit.photos.create!(source: "camera")
  end

  test "starts pending with the neutral effects it asks for" do
    effects = [ { "category" => "lip_color", "colour" => "#B93E22", "intensity" => 60 } ]
    render = @kit.renders.create!(photo: @today, kind: :easy, look_key: "red_lip", effects: effects)

    assert render.reload.pending?
    assert render.easy?
    assert_equal effects, render.effects
    assert_nil render.reference_photo
  end

  test "a transfer keeps its reference photo and a finished render keeps its result" do
    reference = @kit.photos.create!(kind: :reference, source: "upload")
    render = @kit.renders.create!(photo: @today, reference_photo: reference, kind: :transfer)

    render.update!(status: :done, external_id: "task-1", started_at: Time.current,
      result: { io: StringIO.new("jpeg"), filename: "result.jpg", content_type: "image/jpeg" })

    assert_equal reference, render.reload.reference_photo
    assert render.done?
    assert render.result.attached?
  end

  test "destroying a photo destroys the renders made from it" do
    reference = @kit.photos.create!(kind: :reference, source: "upload")
    @kit.renders.create!(photo: @today, kind: :classic)
    @kit.renders.create!(photo: @today, reference_photo: reference, kind: :transfer)

    assert_difference -> { Render.count }, -1 do
      reference.destroy!
    end
    assert_difference -> { Render.count }, -1 do
      @today.destroy!
    end
  end
end
