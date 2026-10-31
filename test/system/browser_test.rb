require "application_system_test_case"

# Proves the browser setup wherever bin/ci runs: a real headless Chrome loads a page and runs script on it.
class BrowserTest < ApplicationSystemTestCase
  test "browser loads the health check" do
    visit "/up"

    assert_equal "complete", evaluate_script("document.readyState")
  end

  test "the browser enforces the content security policy" do
    visit "/up"

    # The health page paints its body green with an inline style attribute, which the policy blocks.
    assert_equal "rgba(0, 0, 0, 0)", evaluate_script("getComputedStyle(document.body).backgroundColor")
  end
end
