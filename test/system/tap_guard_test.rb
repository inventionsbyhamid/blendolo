require "application_system_test_case"
require "support/kit_helpers"

# The repeat-tap guard on its own, on a form added to a real page: no server in the way, only the browser.
class TapGuardTest < ApplicationSystemTestCase
  setup do
    visit "/privacy"
    execute_script <<~JS
      window.submits = 0
      window.clicks = 0
      document.querySelector("main").insertAdjacentHTML("beforeend", `
        <form id="probe" action="/privacy" method="get" data-turbo="false">
          <button id="commit" class="btn btn--primary" data-controller="tap-guard" data-action="click->tap-guard#guard">
            <span class="btn__label">Go</span><span class="btn__working">Working on it</span>
          </button>
        </form>
        <button id="toggle" type="button" class="btn" data-controller="tap-guard" data-action="click->tap-guard#guard"
          data-tap-guard-commit-value="false">Toggle</button>`)
    JS
    wait_for_controller "#commit"
    wait_for_controller "#toggle"
    # Added after the guard, like any action listed after it in data-action.
    execute_script <<~JS
      document.getElementById("probe").addEventListener("submit", (event) => { event.preventDefault(); window.submits++ })
      document.getElementById("toggle").addEventListener("click", () => window.clicks++)
    JS
  end

  test "repeat tap guard blocks second submit" do
    execute_script "const b = document.getElementById('commit'); b.click(); b.click(); b.click()"

    assert_equal 1, evaluate_script("window.submits")
    assert_selector "#commit[disabled][aria-busy=true]", text: "Working on it"
    sleep 1
    find("#commit").click rescue nil
    assert_equal 1, evaluate_script("window.submits"), "a commit button stays held until the next page"
  end

  test "the window follows my hands today" do
    execute_script "document.body.dataset.hands = '0'"
    execute_script "const b = document.getElementById('toggle'); b.click(); b.click()"
    assert_equal 1, evaluate_script("window.clicks")

    sleep 0.6
    execute_script "document.getElementById('toggle').click()"
    assert_equal 2, evaluate_script("window.clicks"), "steady hands: a tap after 500 ms counts"

    execute_script "document.body.dataset.hands = '2'"
    sleep 1.8
    execute_script "document.getElementById('toggle').click()"
    assert_equal 3, evaluate_script("window.clicks")
    sleep 0.5
    execute_script "document.getElementById('toggle').click()"
    assert_equal 3, evaluate_script("window.clicks"), "very shaky or stiff: repeats within 1500 ms are ignored"
    sleep 1.3
    execute_script "document.getElementById('toggle').click()"
    assert_equal 4, evaluate_script("window.clicks")
  end

  test "a held link lets go when its page can't be fetched" do
    execute_script <<~JS
      document.querySelector("main").insertAdjacentHTML("beforeend",
        `<a id="held" href="/privacy" class="btn" data-controller="tap-guard" data-action="click->tap-guard#guard">Go</a>`)
    JS
    wait_for_controller "#held"
    execute_script <<~JS
      const link = document.getElementById("held")
      link.addEventListener("click", (event) => event.preventDefault())
      link.click()
    JS
    assert_selector "#held.is-working[aria-busy=true]"

    execute_script %(document.dispatchEvent(new CustomEvent("turbo:fetch-request-error", { bubbles: true })))
    assert_no_selector "#held.is-working"
    assert_no_selector "#held[aria-busy]"
  end

  private
    def wait_for_controller(selector)
      page.document.synchronize(5) do
        connected = evaluate_script("!!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('#{selector}'), 'tap-guard')")
        raise Capybara::ExpectationNotMet, "tap-guard not connected on #{selector}" unless connected
      end
    end
end

# After a commit tap, every guarded control waits out the window: the neighbouring button, and the control in the
# same place on the next page Turbo shows.
class TapGuardAcrossControlsTest < ApplicationSystemTestCase
  include KitHelpers

  test "a repeat tap on the next page's tile is ignored" do
    kit = make_kit(photo: false)
    visit kit_hand_path(kit, 1)
    assert_selector ".step-header__count", text: "Step 2 of 7"
    page.document.synchronize(5) do
      ready = evaluate_script(<<~JS)
        document.readyState === "complete" && !!window.Turbo &&
          !!window.Stimulus.getControllerForElementAndIdentifier(document.querySelectorAll("ul[aria-labelledby=question] button.tile")[2], "tap-guard")
      JS
      raise Capybara::ExpectationNotMet, "the page's scripts aren't ready" unless ready
    end
    # "A lot" (very shaky: a 1500 ms window from here on), then the tile in the same place on the next question as
    # soon as it shows with its guard.
    execute_script <<~JS
      window.repeatAfter = null
      const third = () => document.querySelectorAll("ul[aria-labelledby=question] button.tile")[2]
      const tapAgain = () => {
        const tile = third()
        const next = document.querySelector(".step-header__count")?.textContent.includes("Step 3 of 7")
        if (!next || !tile || !window.Stimulus.getControllerForElementAndIdentifier(tile, "tap-guard")) return setTimeout(tapAgain, 10)
        window.repeatAfter = performance.now() - window.firstAt
        tile.click()
      }
      window.firstAt = performance.now()
      third().click()
      setTimeout(tapAgain, 10)
    JS

    assert_selector ".step-header__count", text: "Step 3 of 7"
    page.document.synchronize(5) { raise Capybara::ExpectationNotMet, "no repeat tap yet" unless evaluate_script("window.repeatAfter") }
    assert_operator evaluate_script("window.repeatAfter"), :<, 1500, "the repeat came inside the window"
    sleep 1.6
    assert_selector ".step-header__count", text: "Step 3 of 7"
    kit.reload
    assert_equal 2, kit.tremor
    assert_nil kit.pinch, "the repeat tap answered nothing"

    all("ul[aria-labelledby=question] button.tile")[2].click
    assert_selector ".step-header__count", text: "Step 4 of 7"
    assert_equal 2, kit.reload.pinch, "a tap after the window counts"
  end

  test "softer then bolder inside the window sends one change" do
    kit = make_kit(tremor: 2, hands_today: 2)
    visit kit_look_path(kit, "red_lip")
    # The page asks for its previews itself first.
    assert_selector "[id^=render_]", count: 2, wait: 10
    assert_selector "h2", text: "Strength of the easy version: Medium"

    execute_script <<~JS
      const button = (label) => [...document.querySelectorAll("button")].find((el) => el.textContent.trim().startsWith(label))
      button("Softer").click()
      button("Bolder").click()
    JS

    assert_selector "h2", text: "Strength of the easy version: Softer"
    sleep 1
    assert_selector "h2", text: "Strength of the easy version: Softer"
    assert_equal 1, kit.renders.tweak.count, "one tweak, so one unit"
  end
end
