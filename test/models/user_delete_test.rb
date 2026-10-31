require "test_helper"
require "support/account_helpers"

# "Delete my account" is all or nothing: rows go in one transaction, files only after it commits.
class UserDeleteTest < ActiveSupport::TestCase
  include AccountHelpers

  setup do
    @user = make_user(credits: 3)
    @kit = Kit.create!(user: @user)
    @photo = @kit.photos.create!(source: "camera", image: { io: StringIO.new("jpeg"), filename: "today.jpg", content_type: "image/jpeg" })
  end

  test "deletes the kits, credits, account and files" do
    key = @photo.image.key

    @user.destroy_everything!

    assert_not User.exists?(@user.id)
    assert_not Kit.exists?(@kit.id)
    assert_not ActiveStorage::Blob.service.exist?(key)
  end

  test "a failure half way deletes nothing, not even files" do
    key = @photo.image.key
    failing = Module.new { def destroy! = raise(ActiveRecord::InvalidForeignKey, "a kit made meanwhile") }
    @user.singleton_class.prepend(failing)

    assert_raises(ActiveRecord::InvalidForeignKey) { @user.destroy_everything! }

    assert Kit.exists?(@kit.id)
    assert @photo.reload.image.attached?
    assert ActiveStorage::Blob.service.exist?(key)
    assert_equal 3, Credits.balance(@user)
  end
end
