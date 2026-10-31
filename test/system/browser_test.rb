require "application_system_test_case"

# Proves the browser setup wherever bin/ci runs: a real headless Chrome loads a page and runs script on it.
class BrowserTest < ApplicationSystemTestCase
  test "browser loads the health check" do
    visit "/up"

    assert_equal "rgb(0, 128, 0)", evaluate_script("getComputedStyle(document.body).backgroundColor")
  end
end
