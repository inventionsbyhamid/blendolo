require "application_system_test_case"

# The offline shell's service worker answers every page load, so it turns on navigation preload: the page is asked for
# while the worker starts rather than after.
class ServiceWorkerTest < ApplicationSystemTestCase
  test "the service worker turns on navigation preload and pages still load through it" do
    visit root_path

    enabled = evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const deadline = Date.now() + 5000
      const check = (registration) => registration.navigationPreload.getState().then(({ enabled }) =>
        enabled || Date.now() > deadline ? done(enabled) : setTimeout(() => check(registration), 50))
      navigator.serviceWorker.ready.then(check).catch((error) => done(String(error)))
    JS
    assert_equal true, enabled

    # The next page load is a navigation the worker answers, with the preloaded response.
    visit privacy_path
    assert_selector "h1", text: "Your photos, your call"
    assert evaluate_script("navigator.serviceWorker.controller !== null"), "the page loaded through the worker"
  end
end
