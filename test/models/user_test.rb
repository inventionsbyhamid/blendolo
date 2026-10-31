require "test_helper"
require "support/account_helpers"

class UserTest < ActiveSupport::TestCase
  include AccountHelpers

  def auth(uid: "g-1", name: "Rosa Diaz", email: " Rosa@Example.com ")
    OmniAuth::AuthHash.new(provider: "google_oauth2", uid:, info: { name:, email:, image: "https://lh3.googleusercontent.com/a/x" })
  end

  test "from omniauth makes the account once and keeps it up to date" do
    user = User.from_omniauth(auth)
    assert_equal [ "google_oauth2", "g-1", "rosa@example.com", "Rosa Diaz" ], [ user.provider, user.uid, user.email, user.name ]

    same = User.from_omniauth(auth(name: "Rosa D"))
    assert_equal user, same
    assert_equal "Rosa D", same.name
    assert_equal 1, User.count
  end

  test "an answer with no email is refused" do
    assert_raises(ActiveRecord::RecordInvalid) { User.from_omniauth(auth(email: nil)) }
  end

  test "first name and clinic status" do
    user = make_user(name: "Rosa Maria Diaz")
    assert_equal "Rosa", user.first_name
    assert_equal "june", User.new(email: "june@example.com").first_name

    assert_not user.clinic?
    user.update!(clinic_until: 1.day.from_now)
    assert user.clinic?
    user.update!(clinic_until: 1.minute.ago)
    assert_not user.clinic?
  end

  test "claiming takes a kit in no account, never another account's kit or an example" do
    rosa, june = make_user, make_user
    guest = Kit.create!
    junes = Kit.create!(user: june)

    assert rosa.claim!(guest)
    assert_equal rosa, guest.reload.user
    assert rosa.claim!(guest), "already hers"
    assert_not june.claim!(guest)
    assert_not rosa.claim!(junes)
    assert_equal june, junes.reload.user

    example = Kit.new(path: :example, example_key: "rosa", building_example: true).tap(&:save!)
    assert_not rosa.claim!(example)
    assert_nil example.reload.user_id
  end

  test "a label is trimmed and 40 characters at most" do
    kit = Kit.create!(label: "  Mrs   Patel  ")
    assert_equal "Mrs Patel", kit.label

    kit.label = "x" * 41
    assert_not kit.valid?
    kit.label = "   "
    assert kit.valid?
    assert_nil kit.label
  end

  test "delete my account deletes its kits, photos and credits" do
    user = make_user(credits: 5)
    kit = Kit.create!(user:)
    photo = kit.photos.create!(source: "upload", image: { io: file_fixture("face.jpg").open, filename: "face.jpg", content_type: "image/jpeg" })
    blob = photo.image.blob
    other = Kit.create!

    user.destroy_everything!

    assert_not User.exists?(user.id)
    assert_not Kit.exists?(kit.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_equal 0, CreditEntry.where(user_id: user.id).count
    assert Kit.exists?(other.id)
  end
end
