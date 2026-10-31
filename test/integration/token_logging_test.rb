require "test_helper"
require "support/kit_helpers"

# Kit and share tokens open a person's kit: they never reach the log, in paths or parameters.
class TokenLoggingTest < ActionDispatch::IntegrationTest
  include KitHelpers

  test "share tokens in paths are filtered from the started line" do
    kit = make_kit
    share = kit.shares.create!(audience: :helper, scope: :routine_only)
    share.revoke!

    log = capture_log do
      post restore_kit_share_path(kit, share.token)
      delete kit_share_path(kit, share.token)
      get public_share_path(share.token)
    end

    assert_includes log, "/k/[FILTERED]/shares/[FILTERED]/restore"
    assert_includes log, "/s/[FILTERED]"
    assert_not_includes log, kit.token
    assert_not_includes log, share.token
  end

  test "a kit's share list keeps its path" do
    assert_equal "/k/[FILTERED]/shares", filtered("/k/abc123/shares")
    assert_equal "/k/[FILTERED]/shares/[FILTERED]/restore", filtered("/k/abc123/shares/def456/restore")
  end

  private
    def filtered(path)
      ActionDispatch::Request.new(Rack::MockRequest.env_for(path)).filtered_path
    end

    def capture_log
      io = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io))
      yield
      io.string
    ensure
      Rails.logger = original
    end
end
