require "test_helper"

class ShareTest < ActiveSupport::TestCase
  setup { @kit = Kit.create! }

  test "share live excludes revoked and expired" do
    live = @kit.shares.create!(audience: :helper)
    revoked = @kit.shares.create!(audience: :family)
    revoked.revoke!
    expired = travel_to(31.days.ago) { @kit.shares.create!(audience: :therapist) }

    assert_equal [ live ], Share.live.to_a
    assert live.live?
    assert_not revoked.live?
    assert_not expired.live?
  end

  test "expires after 30 days with its own token and routine only by default" do
    freeze_time do
      share = @kit.shares.create!(audience: :therapist)
      assert_equal 30.days.from_now, share.expires_at
      assert_equal 24, share.token.length
      assert share.routine_only?
      assert share.therapist?
    end
  end

  test "can include photos" do
    assert @kit.shares.create!(audience: :family, scope: :routine_and_photos).routine_and_photos?
  end
end
