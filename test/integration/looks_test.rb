require "test_helper"
require "support/kit_helpers"

class LooksTest < ActionDispatch::IntegrationTest
  include KitHelpers

  setup { KitHelpers::CountRequests.count = 0 }

  test "get look page creates no renders" do
    kit = make_kit(tremor: 2)

    assert_no_difference -> { Render.count } do
      get kit_look_path(kit, "red_lip")
      get kit_look_path(kit, "red_lip", level: 1)
    end
    assert_response :success
    assert_equal 0, KitHelpers::CountRequests.count
    assert_select "form[action=?][data-controller=autostart] button", previews_kit_look_path(kit, "red_lip"), text: /Show it on my face/
    assert_select ".render", text: /Getting your photo ready/, count: 2
  end

  test "hover prefetch disabled meta present" do
    get root_path
    assert_select "meta[name=turbo-prefetch][content=false]"

    kit = make_kit(tremor: 2)
    get kit_look_path(kit, "red_lip"), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_response :no_content
    assert_equal 0, kit.renders.count
  end

  test "show it on my face makes the classic and easy renders once" do
    kit = make_kit(tremor: 2)

    assert_difference -> { kit.renders.count }, 2 do
      2.times { post previews_kit_look_path(kit, "red_lip") }
    end
    assert_redirected_to kit_look_path(kit, "red_lip")
    assert_equal %w[classic easy], kit.renders.order(:id).map(&:kind)
    assert_equal 2, KitHelpers::CountRequests.count

    follow_redirect!
    assert_select "##{ActionView::RecordIdentifier.dom_id(kit.renders.first)}"
    assert_select "form[data-controller=autostart]", count: 0
    assert_select ".honest", "Preview, not a promise"
  end

  test "the easy render follows the hand answers" do
    kit = make_kit(tremor: 0)
    post previews_kit_look_path(kit, "red_lip")
    kit.update!(tremor: 2, near_vision: 2)
    post previews_kit_look_path(kit, "red_lip")

    easy = kit.renders.easy.order(:id)
    assert_equal 2, easy.count
    assert_not_equal easy.first.effects, easy.last.effects
  end

  test "a look needs today's photo first" do
    kit = make_kit(photo: false)

    get kit_look_path(kit, "red_lip")
    assert_redirected_to new_kit_photo_path(kit)
  end

  test "an unknown look is 404" do
    get kit_look_path(make_kit, "no_such_look")
    assert_response :not_found
  end

  test "looks are listed easiest first" do
    kit = make_kit(tremor: 2)

    get kit_looks_path(kit)
    assert_response :success
    names = css_select(".tiles--looks .tile__label").map(&:text)
    eases = LookForKit.easiest_first(kit).map { |look| look.classic_ease[:ease] }
    assert_equal eases.sort.reverse, eases
    assert_equal LookForKit.easiest_first(kit).map(&:name), names
  end

  test "softer and bolder make one tweak render per level" do
    kit = make_kit(tremor: 2)

    assert_difference -> { kit.renders.tweak.count }, 1 do
      post tweak_kit_look_path(kit, "red_lip"), params: { direction: "bolder", level: 0 }
      post tweak_kit_look_path(kit, "red_lip"), params: { direction: "bolder", level: 0 }
    end
    assert_redirected_to kit_look_path(kit, "red_lip", level: 1)
  end

  test "make this my routine stores the easy steps in order, tidy up last" do
    kit = make_kit(tremor: 2)

    post kit_routine_path(kit), params: { look_key: "red_lip" }
    assert_redirected_to kit_routine_path(kit)
    kit.reload
    assert_equal "red_lip", kit.chosen_look_key
    assert_equal "fixup", kit.routine.last["step"]
    assert_not_includes kit.routine.map { |entry| entry["step"] }, "liquid_liner_wing"

    get step_kit_routine_path(kit, 1)
    assert_response :success
    assert_select ".step-header__count", "Step 1 of #{kit.routine.size}"
  end

  test "try again asks the provider again for a preview that took too long" do
    kit = make_kit(tremor: 2)
    post previews_kit_look_path(kit, "red_lip")
    render = kit.renders.classic.sole
    render.update!(status: :failed, failure_reason: "timeout")
    KitHelpers::CountRequests.count = 0

    get kit_look_path(kit, "red_lip")
    assert_select "##{ActionView::RecordIdentifier.dom_id(render)}", /That took too long on our side/
    post try_again_kit_render_path(kit, render), headers: { "HTTP_REFERER" => kit_look_path(kit, "red_lip") }

    assert_redirected_to kit_look_path(kit, "red_lip")
    assert_equal 1, KitHelpers::CountRequests.count
    assert render.reload.pending?
  end

  test "try again leaves a photo problem alone" do
    kit = make_kit(tremor: 2)
    post previews_kit_look_path(kit, "red_lip")
    render = kit.renders.classic.sole
    render.update!(status: :failed, failure_reason: "eyes_closed")
    KitHelpers::CountRequests.count = 0

    post try_again_kit_render_path(kit, render)
    assert_equal 0, KitHelpers::CountRequests.count
  end
end
