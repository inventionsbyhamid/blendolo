require "application_system_test_case"
require "support/kit_helpers"

class LooksSystemTest < ApplicationSystemTestCase
  include KitHelpers

  setup do
    @kit = make_kit(tremor: 2, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 1)
  end

  test "looks sorted easiest first for tremor profile" do
    on_phone { visit kit_looks_path(@kit) }

    expected = LookForKit.easiest_first(@kit)
    assert_equal expected.map(&:name), all(".tiles--looks .tile__label").map(&:text)
    assert_equal expected.map(&:classic_words), all(".tiles--looks .tile__badge").map(&:text)
    eases = expected.map { |look| look.classic_ease[:ease] }
    assert_equal eases.sort.reverse, eases
    assert_selector ".tiles--looks .tile__hint", text: "Hardest step:", minimum: 1
    shot "looks"
  end

  test "look page shows classic and easy" do
    visit kit_look_path(@kit, "red_lip")
    classic, easy = @kit.renders.order(:id).to_a
    assert_equal %w[classic easy], [ classic.kind, easy.kind ]
    assert_selector "##{dom_id(classic)}", text: "This takes about a minute"

    [ classic, easy ].each do |render|
      render.result.attach(io: file_fixture("face.jpg").open, filename: "#{render.kind}.jpg", content_type: "image/jpeg")
      render.update!(status: :done)
    end
    on_phone { visit kit_look_path(@kit, "red_lip") }

    within(".compare") do
      assert_selector "##{dom_id(classic)} img.render__image"
      assert_selector "##{dom_id(easy)} img.render__image"
      assert_text "Preview, not a promise"
      click_on "Easy version"
      assert_selector ".compare__stage[data-show=easy]"
      assert_no_selector "##{dom_id(classic)} img", visible: true
    end
    assert_selector ".ease-change", text: /\A\S.*→.*\S\z/
    shot "look"
  end

  test "swaps listed in plain words" do
    visit kit_look_path(@kit, "red_lip")
    look = LookForKit.find(@kit, "red_lip")

    within(".swaplist") do
      look.swaps.each do |swap|
        assert_text swap[:from].name
        assert_text swap[:to]&.name || "Left out"
      end
      assert_text "Why it's easier:"
    end
    look.unswappable.each { |step| assert_text step.no_swap_why }
  end

  test "make routine" do
    visit kit_look_path(@kit, "red_lip")
    click_on "Make this my routine"

    assert_selector "h1", text: "Your routine"
    assert_equal "red_lip", @kit.reload.chosen_look_key
    assert_equal "fixup", @kit.routine.last["step"]
    assert_selector ".linklist li", count: @kit.routine.size
  end

  private
    def dom_id(record) = ActionView::RecordIdentifier.dom_id(record)

    def on_phone
      page.current_window.resize_to(390, 844)
      yield
    end

    teardown { page.current_window.resize_to(1400, 1400) }
end
