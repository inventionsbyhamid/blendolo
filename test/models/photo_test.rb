require "test_helper"

class PhotoTest < ActiveSupport::TestCase
  setup { @kit = Kit.create! }

  test "stores the image and the colours sampled in the browser" do
    photo = @kit.photos.create!(
      kind: :reference, source: "upload", sha256: "a" * 64, width: 1200, height: 1600,
      sampled: { lips: "#B93E22", lids: "#6A5D53", cheeks: "#FFE2CF", skin: "#E0B89A" },
      image: { io: StringIO.new("jpeg"), filename: "old.jpg", content_type: "image/jpeg" }
    )

    assert photo.reload.reference?
    assert photo.image.attached?
    assert_equal "#B93E22", photo.sampled["lips"]
    assert_equal [ photo ], @kit.photos.reference.to_a
  end

  test "defaults to today's photo with nothing sampled" do
    photo = @kit.photos.create!(source: "camera")
    assert photo.today?
    assert_equal({}, photo.sampled)
  end

  test "accepts only known sources" do
    assert_not @kit.photos.new(source: "url").valid?
  end

  test "accepts only hex colours for known regions" do
    assert_not @kit.photos.new(source: "camera", sampled: { lips: "red" }).valid?
    assert_not @kit.photos.new(source: "camera", sampled: { hair: "#000000" }).valid?
    assert @kit.photos.new(source: "camera", sampled: { skin: "#a0b1c2" }).valid?
  end
end
