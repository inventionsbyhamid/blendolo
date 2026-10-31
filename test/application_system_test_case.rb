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
  end
end
