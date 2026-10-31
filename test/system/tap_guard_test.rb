require "application_system_test_case"

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
    sleep 1.6
    execute_script "document.getElementById('toggle').click()"
    assert_equal 3, evaluate_script("window.clicks")
    sleep 0.9
    execute_script "document.getElementById('toggle').click()"
    assert_equal 3, evaluate_script("window.clicks"), "very shaky or stiff: repeats within 1500 ms are ignored"
    sleep 0.8
    execute_script "document.getElementById('toggle').click()"
    assert_equal 4, evaluate_script("window.clicks")
  end

  private
    def wait_for_controller(selector)
      page.document.synchronize(5) do
        connected = evaluate_script("!!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('#{selector}'), 'tap-guard')")
        raise Capybara::ExpectationNotMet, "tap-guard not connected on #{selector}" unless connected
      end
    end
end
