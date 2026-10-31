require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
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
