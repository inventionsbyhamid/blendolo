require "application_system_test_case"
require "support/kit_helpers"
require "support/tremor_checks"

class KitFlowTest < ApplicationSystemTestCase
  include KitHelpers
  include TremorChecks

  test "start to consent to hands" do
    visit "/"
    click_on "Start"
    assert_selector "h1", text: "Who is this for?"

    click_on "For me"
    assert_selector ".step-header__count", text: "Step 1 of 7"
    assert_selector "h1", text: "Before we start"

    click_on "Agree, keep it for 30 days"
    assert_selector ".step-header__count", text: "Step 2 of 7"
    assert_selector "h1", text: "Do your hands shake?"

    click_on "A lot"
    assert_selector ".step-header__count", text: "Step 3 of 7"
    kit = Kit.sole
    assert kit.consented_at?
    assert_equal 2, kit.tremor
    assert_equal 2, kit.hands_today, "the tremor answer sets My hands today"
    assert_selector "body[data-hands='2']"

    click_on "Back"
    assert_selector ".tile--chosen", text: "A lot"
  end

  test "repeat tap guard blocks second submit" do
    visit start_path
    assert_selector ".tile", text: "For me"
    execute_script "const b = [...document.querySelectorAll('button.tile')].find((el) => el.textContent.includes('For me')); b.click(); b.click(); b.click()"

    assert_selector "h1", text: "Before we start"
    assert_equal 1, Kit.count
  end

  test "hand answers change look order" do
    kit = make_kit(tremor: 0, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
    visit kit_looks_path(kit)
    before = all(".tiles--looks .tile__label").map(&:text)
    assert_equal LookForKit.easiest_first(kit).map(&:name), before

    visit kit_hand_path(kit, 2)
    click_on "Yes"
    assert_selector "h1", text: "Do you mostly use one hand?"
    click_on "Mostly left"
    assert_selector "h1", text: "Do your arms tire quickly?"

    visit kit_looks_path(kit)
    after = all(".tiles--looks .tile__label").map(&:text)
    assert_equal LookForKit.easiest_first(kit.reload).map(&:name), after
    assert_not_equal before, after
  end

  test "hands today changes target size" do
    kit = make_kit
    on_a_phone do
      visit kit_path(kit)
      assert_selector "body[data-hands='1']"
      assert_equal 88, button_height("Looks")

      within("main") { click_on "Steady" }
      assert_selector "body[data-hands='0']"
      assert_equal 64, button_height("Looks")
      assert_targets_at_least 64

      within("main") { click_on "Very shaky or stiff" }
      assert_selector "body[data-hands='2']"
      assert_equal 104, button_height("Looks")
      assert_equal 2, kit.reload.hands_today
    end
  end

  test "hands today is in the header menu" do
    kit = make_kit
    visit kit_routine_path(kit) # no routine yet: goes to looks, with the menu
    find("details.menu > summary").click
    within("details.menu") { click_on "Very shaky or stiff" }

    assert_selector "body[data-hands='2']"
    assert_current_path kit_looks_path(kit)
  end

  test "delete everything confirms and 404s after" do
    kit = make_kit
    visit kit_path(kit)
    within("main") { click_on "Delete everything" }

    assert_selector "h1", text: "Delete everything?"
    assert Kit.exists?(kit.id), "nothing is deleted before the confirm page"
    click_on "Yes, delete everything"

    assert_selector ".flash", text: "Everything is deleted"
    assert_not Kit.exists?(kit.id)
    showing_public_error_pages { visit kit_path(kit) }
    assert_text "This page has wandered off."
  end

  private
    def button_height(label)
      find("main a.btn, main button.btn", text: label, match: :first).evaluate_script("Math.round(this.getBoundingClientRect().height)")
    end
end
