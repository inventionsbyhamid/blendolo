require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Taps at a person's pace: a Capybara click waits out what's left of the repeat-tap window since the previous one
  # (tap_guard_controller.js ignores any tap that soon after a commit tap, on this page or the next). Tests of the
  # guard itself tap with JavaScript, which doesn't wait.
  module HumanPace
    WINDOWS = { "0" => 0.5, "1" => 0.8, "2" => 1.5 }.freeze
    MARGIN = 0.1
    mattr_accessor :last_click_at

    def click(*, **)
      if (last = HumanPace.last_click_at) && (elapsed = HumanPace.now - last) < WINDOWS.values.max + MARGIN
        hands = session.evaluate_script("document.body ? document.body.dataset.hands : null")
        remaining = WINDOWS.fetch(hands.to_s, WINDOWS["1"]) + MARGIN - elapsed
        sleep remaining if remaining.positive?
      end
      super
    ensure
      HumanPace.last_click_at = HumanPace.now
    end

    def self.now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
  Capybara::Node::Element.prepend(HumanPace) unless Capybara::Node::Element <= HumanPace

  # The CI container (script/ci/Dockerfile) has Debian's Chromium and its chromedriver instead of Google Chrome.
  # Selenium is pointed at the driver before driven_by looks for one, so it doesn't try to download a browser, and
  # Chromium runs without its sandbox because the container runs as root.
  CHROMIUM = "/usr/bin/chromium"
  CHROMEDRIVER = "/usr/bin/chromedriver"

  if File.exist?(CHROMIUM)
    require "selenium/webdriver"
    Selenium::WebDriver::Chrome::Service.driver_path = CHROMEDRIVER
  end

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    if File.exist?(CHROMIUM)
      options.binary = CHROMIUM
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
    end
    # A fake camera (a moving test pattern) that needs no permission prompt, for the hands-free capture tests.
    options.add_argument("--use-fake-device-for-media-stream")
    options.add_argument("--use-fake-ui-for-media-stream")
  end

  SCREENS = Rails.root.join("tmp/screenshots/screens")

  # The test environment shows detailed errors; production shows public/404.html.
  def showing_public_error_pages
    env_config = Rails.application.env_config
    detailed = env_config["action_dispatch.show_detailed_exceptions"]
    env_config["action_dispatch.show_detailed_exceptions"] = false
    yield
  ensure
    env_config["action_dispatch.show_detailed_exceptions"] = detailed
  end

  # Saves a picture of the whole page for a person to look at (kept in tmp/screenshots/screens on the CI host).
  def shot(name)
    SCREENS.mkpath
    browser = page.driver.browser
    size = browser.execute_cdp("Page.getLayoutMetrics")["cssContentSize"]
    clip = { x: 0, y: 0, width: size["width"], height: [ size["height"], 6000 ].min, scale: 1 }
    png = browser.execute_cdp("Page.captureScreenshot", format: "png", captureBeyondViewport: true, clip:)["data"]
    SCREENS.join("#{name}.png").binwrite(png.unpack1("m"))
  end
end
