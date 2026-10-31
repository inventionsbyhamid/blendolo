require "application_system_test_case"
require "support/kit_helpers"

class SharesSystemTest < ApplicationSystemTestCase
  include KitHelpers

  setup do
    @kit = make_kit(tremor: 2, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
    @kit.update!(chosen_look_key: "red_lip", routine: RoutinePlan.from(LookForKit.find(@kit, "red_lip").easy_steps))
  end

  teardown { page.current_window.resize_to(1400, 1400) }

  test "create share and view publicly" do
    page.current_window.resize_to(390, 844)
    visit kit_path(@kit)
    click_on "Share with a helper"
    assert_selector "h1", text: "Who is the link for?"
    click_on "A helper"
    assert_selector "h1", text: "What can they see?"
    click_on "The routine only"

    assert_selector "h1", text: "Your link is ready"
    assert_selector "svg.qr"
    share = @kit.shares.sole
    assert share.helper? && share.routine_only?
    link = find("input.link-box").value
    assert_equal public_share_url(share.token, host: Capybara.current_session.server.host, port: Capybara.current_session.server.port), link
    shot "share-made"

    visit public_share_path(share.token)
    assert_selector "h1", text: "A makeup routine, shared with you"
    assert_selector ".instruction", text: RoutinePlan.steps(@kit).first.instruction
    assert_no_selector "img[alt='Their photo']"
    assert_no_selector "details.menu"
    shot "share-public"
  end

  test "revoke share" do
    share = @kit.shares.create!(audience: :family, scope: :routine_only)
    visit kit_shares_path(@kit)
    click_on "Switch this link off"

    assert_selector ".flash", text: "That link is switched off."
    assert share.reload.revoked_at?
    showing_public_error_pages { visit public_share_path(share.token) }
    assert_text "This page has wandered off."
  end

  test "brands page renders example" do
    page.current_window.resize_to(390, 844)
    visit brands_path

    assert_selector "h1", text: "Ease tags for your products"
    assert_selector "pre.code", text: "/api/ease_tags?closure=pull_cap"
    assert_selector "pre.code", text: "\"pinch_grip\""
    assert_selector "pre.code", text: "\"label\": \"No pinch grip\""
    shot "brands"
  end
end
