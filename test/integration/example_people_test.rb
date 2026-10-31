require "test_helper"
require "support/kit_helpers"

class ExamplePeopleTest < ActionDispatch::IntegrationTest
  include KitHelpers

  setup { KitHelpers::CountRequests.count = 0 }

  test "example kit never calls provider" do
    post start_example_path("rosa")
    kit = Examples.kit_for("rosa")
    assert_redirected_to kit_path(kit)
    assert kit.example?

    assert_no_difference [ -> { ProviderCall.count }, -> { Render.count } ] do
      get kit_look_path(kit, "red_lip")
      assert_response :success
      kit.renders.where(look_key: "red_lip").each do |render|
        assert_select "##{ActionView::RecordIdentifier.dom_id(render)} img.render__image"
      end

      get kit_look_path(kit, "red_lip", level: 1)
      assert_select "#missing_tweak", /isn't stored for the example person/

      get kit_signature_path(kit)
      assert_select "##{ActionView::RecordIdentifier.dom_id(kit.renders.transfer.sole)} img.render__image"
    end
    assert_equal 0, KitHelpers::CountRequests.count
  end

  test "the example kit is shared and stays as it is" do
    post start_example_path("june")
    post start_example_path("june")
    kit = Examples.kit_for("june")
    answers = kit.hand_answers

    patch kit_hand_path(kit, 1), params: { answer: 2 }
    post kit_routine_path(kit), params: { look_key: "red_lip" }
    post kit_shares_path(kit), params: { audience: "helper" }
    delete kit_path(kit)

    assert Kit.exists?(kit.id)
    assert_equal answers, kit.reload.hand_answers
    assert_empty kit.routine
    assert_equal 1, kit.shares.count, "only the example's own demo link"
    follow_redirect!
    assert_select ".flash", /June's example kit, so it stays as it is/
  end

  test "an example kit shows what a helper sees, read only" do
    kit = Examples.rebuild!(:rosa)
    share = kit.shares.sole
    assert share.routine_and_photos?
    assert_equal kit.purge_after, share.expires_at

    get kit_path(kit)
    assert_select "a[href=?]", public_share_path(share.token), text: /See what a helper sees/

    get public_share_path(share.token)
    assert_response :success
    assert_select "h1", "A makeup routine, shared with you"
    assert_select ".honest", /Example person/
    assert_select "img.render__image", 2
    assert_select "ol li.card", RoutinePlan.steps(kit).size

    delete kit_share_path(kit, share.token)
    assert share.reload.live?, "nobody can switch the example's link off"
  end

  test "an example person's routine follows their chosen look" do
    kit = Examples.kit_for("rosa")

    post kit_routine_path(kit), params: { look_key: "red_lip" }
    assert_redirected_to kit_routine_path(kit)
    follow_redirect!
    assert_response :success
    assert_select ".linklist li", minimum: 2
  end

  test "my hands today on an example kit is kept for this visitor only" do
    kit = Examples.kit_for("amara")

    patch kit_hands_today_path(kit), params: { hands_today: 2 }
    assert_equal 1, kit.reload.hands_today
    get kit_path(kit)
    assert_select "body[data-hands='2']"
  end

  test "example pages name the person and say the photos are AI generated" do
    get examples_path
    assert_select ".tile__label", "Rosa"
    assert_select ".honest", /AI generated/

    get example_path("amara")
    assert_select "h1", "Amara"
    get example_path("amara", soon: 1)
    assert_select ".empty__title", "Example coming soon"
  end

  test "a write the models refuse on an example kit ends with the example message" do
    kit = Examples.kit_for("rosa")
    # Past the controller's own check, the model refuses: the visitor sees the same message.
    HandsController.define_method(:keep_example_kits_as_they_are) { nil }
    patch kit_hand_path(kit, 2), params: { answer: 2 }, headers: { "HTTP_REFERER" => kit_hand_path(kit, 2) }

    assert_redirected_to kit_hand_path(kit, 2)
    assert_equal "This is Rosa's example kit, so it stays as it is. Start your own kit to make it yours.", flash[:notice]
    assert_equal Examples.fetch(:rosa).hands[:pinch], kit.reload.pinch
  ensure
    HandsController.remove_method(:keep_example_kits_as_they_are)
  end

  test "rosa's red lip is some care in its easy version, with mascara as an optional step" do
    kit = Examples.kit_for("rosa")
    get kit_look_path(kit, "red_lip")

    assert_select ".ease-change", text: /Hard.*Some care/m
    assert_select ".meter", text: /Easy version\s*Some care/
    assert_select ".optional-step", text: /Mascara on the upper lashes: Hard for her hands|Mascara on the upper lashes: Hard for your hands/
    assert_select ".optional-step", text: /Optional\. Skip it on shaky days\./
    assert_select ".optional-step", text: /#{Regexp.escape(Ease::StepCatalogue.fetch("mascara_upper").no_swap_why)}/
  end

  test "an optional step's card says it is optional" do
    kit = Examples.kit_for("rosa")
    entries = RoutinePlan.entries(kit)
    number = entries.index { |entry| entry["step"] == "mascara_upper" } + 1
    assert entries[number - 1]["optional"]

    get step_kit_routine_path(kit, number)
    assert_select ".chip", "Optional"
    assert_select "p", "Optional. Skip it on shaky days."
    get kit_routine_path(kit)
    assert_select ".linklist small", text: /optional/
  end
end
