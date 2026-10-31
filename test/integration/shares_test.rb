require "test_helper"
require "support/kit_helpers"

class SharesTest < ActionDispatch::IntegrationTest
  include KitHelpers

  setup do
    @kit = make_kit(tremor: 2)
    post kit_routine_path(@kit), params: { look_key: "red_lip" }
  end

  test "revoked share 404" do
    share = @kit.shares.create!(audience: :helper, scope: :routine_only)
    get public_share_path(share.token)
    assert_response :success

    delete kit_share_path(@kit, share.token)
    get public_share_path(share.token)
    assert_response :not_found
  end

  test "expired share 404" do
    share = @kit.shares.create!(audience: :family, scope: :routine_only)

    travel Share::LIFETIME + 1.minute do
      get public_share_path(share.token)
      assert_response :not_found
    end
  end

  test "public share respects scope" do
    routine_only = @kit.shares.create!(audience: :helper, scope: :routine_only)
    with_photos = @kit.shares.create!(audience: :therapist, scope: :routine_and_photos)

    get public_share_path(routine_only.token)
    assert_select ".instruction", minimum: 1
    assert_select "img[alt='Their photo']", count: 0
    assert_select "details.menu", count: 0
    assert_select "meta[name=robots][content='noindex, nofollow']"

    get public_share_path(with_photos.token)
    assert_select "img[alt='Their photo']", count: 1
  end

  test "a share of a deleted kit is gone" do
    share = @kit.shares.create!(audience: :helper, scope: :routine_only)
    @kit.destroy_everything!

    get public_share_path(share.token)
    assert_response :not_found
  end

  test "making a share twice in a row gives one link" do
    assert_difference -> { @kit.shares.count }, 1 do
      2.times { post kit_shares_path(@kit), params: { audience: "helper", scope: "routine_only" } }
    end
  end
end
