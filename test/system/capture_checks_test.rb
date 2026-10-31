require "application_system_test_case"
require "support/kit_helpers"
require "support/fake_camera"

# Hands-free capture with the real face checks: MediaPipe, loaded from its CDN as in production, runs in a worker and
# looks at Chrome's fake camera showing a face (an example person's photo). It's the one test whose browser needs the
# network (for MediaPipe and its face model); it's skipped when the CDN can't be reached.
class CaptureChecksTest < ApplicationSystemTestCase
  include KitHelpers

  FACE = Rails.root.join("db/seeds/files/examples/amara_today.jpg")

  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ], options: { name: :headless_chrome_face } do |options|
    if File.exist?(CHROMIUM)
      options.binary = CHROMIUM
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
    end
    camera = Rails.root.join("tmp/fake-camera-#{Process.pid}.y4m")
    camera.dirname.mkpath
    options.add_argument("--use-fake-device-for-media-stream")
    options.add_argument("--use-fake-ui-for-media-stream")
    options.add_argument("--use-file-for-fake-video-capture=#{FakeCamera.write(FACE, camera)}")
  end

  setup do
    @kit = make_kit(photo: false, tremor: 0, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
    @capture_checks = Rails.application.config.x.capture_checks
    Rails.application.config.x.capture_checks = true
  end

  teardown { Rails.application.config.x.capture_checks = @capture_checks }

  test "the worker checks the camera and the page takes the photo by itself" do
    visit new_kit_photo_path(@kit)
    skip "MediaPipe's CDN can't be reached from the browser" unless mediapipe_reachable?
    assert_selector "[data-capture-state=live]", wait: 10
    execute_script <<~JS
      window.captureMessages = []
      const message = document.querySelector("[data-capture-target=message]")
      new MutationObserver(() => window.captureMessages.push(message.textContent))
        .observe(message, { childList: true, characterData: true, subtree: true })
    JS

    assert_selector "[data-capture-state=review]", wait: 90
    assert_includes evaluate_script("window.captureMessages"), "Got it"
    assert_equal "worker", evaluate_script(<<~JS)
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~=capture]"), "capture").gate.kind
    JS

    click_on "Use this photo"
    assert_current_path kit_looks_path(@kit), wait: 10
    photo = @kit.photos.today.sole
    assert_equal "camera", photo.source
    assert_match(/\A#\h{6}\z/, photo.sampled["skin"], "skin colour sampled where the worker found the face")
  end

  private
    def mediapipe_reachable?
      using_wait_time(10) do
        evaluate_async_script(<<~JS, Rails.application.config.x.mediapipe.package_url)
          const [url, done] = arguments
          fetch(`${url}package.json`, { signal: AbortSignal.timeout(8000) }).then((response) => done(response.ok), () => done(false))
        JS
      end
    end
end
