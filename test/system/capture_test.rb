require "application_system_test_case"
require "support/kit_helpers"
require "support/face_results"

# Hands-free capture with Chrome's fake camera (a test pattern, no face), and the capture checks and colour sampler
# on made-up Face Landmarker results. MediaPipe itself loads from a CDN and isn't loaded in tests.
class CaptureTest < ApplicationSystemTestCase
  include KitHelpers

  setup do
    @kit = make_kit(photo: false, tremor: 0, pinch: 0, one_hand: 0, fatigue: 0, near_vision: 0)
  end

  test "capture with fake camera uploads one photo" do
    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=live]", wait: 10
    assert_selector "[data-capture-target=message]", text: "Tap Take the photo when you're ready"
    shot "capture-live"

    click_on "Take the photo"
    assert_selector "[data-capture-state=review]", wait: 10
    assert_selector "img[data-capture-target=reviewImage][src^='blob:']"
    shot "capture-review"
    execute_script "const b = [...document.querySelectorAll('button')].find((el) => el.textContent.includes('Use this photo')); b.click(); b.click(); b.click()"

    assert_current_path kit_looks_path(@kit), wait: 10
    photo = @kit.photos.today.sole
    assert_equal "camera", photo.source
    assert_equal 0, photo.width % 8
    assert_operator photo.height, :<, 1080
  end

  test "camera denied shows choose photo" do
    page.driver.browser # start the browser before talking to it
    script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException("Denied", "NotAllowedError"))
    JS

    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=no-camera]", wait: 10
    assert_text "We can't use the camera here. Choose a photo instead."
    assert_no_selector "button", text: "Take the photo"
    assert_selector "label", text: "Choose a photo"
    shot "capture-no-camera"

    find("input[data-capture-target=choose]", visible: :all).attach_file(file_fixture("face.jpg"))
    assert_selector "[data-capture-state=review]", wait: 10
    click_on "Use this photo"

    assert_current_path kit_looks_path(@kit), wait: 10
    assert_equal "upload", @kit.photos.today.sole.source
  ensure
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end

  test "a double tap on spoken help switches it once" do
    visit new_kit_photo_path(@kit)
    assert_selector "[data-capture-state=live]", wait: 10
    execute_script "const b = document.querySelector('[data-capture-target=speech]'); b.click(); b.click()"

    assert_selector "[data-capture-target=speech][aria-pressed=false]", text: "Spoken help: off"
  end

  test "leaving the page turns the camera off" do
    visit new_kit_photo_path(@kit)
    assert_selector "[data-capture-state=live]", wait: 10
    execute_script <<~JS
      const capture = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~=capture]"), "capture")
      window.cameraTracks = capture.stream.getTracks()
    JS
    click_on "Finish later"

    assert_current_path kit_path(@kit)
    assert evaluate_script("window.cameraTracks.length > 0 && window.cameraTracks.every((track) => track.readyState === 'ended')")
  end

  test "choose a photo opens the file picker from its label, once per tap" do
    [ new_kit_photo_path(@kit), new_kit_photo_path(@kit, kind: "reference") ].each do |path|
      visit path
      assert_selector "[data-capture-state=live], [data-capture-state=choose], [data-capture-state=no-camera]", wait: 10
      wait_for_guard
      # Listen after the guard, as the browser's own file picker would act: a click it didn't cancel opens it.
      execute_script <<~JS
        window.pickerClicks = []
        document.querySelector("input[data-capture-target=choose]")
          .addEventListener("click", (event) => { window.pickerClicks.push(!event.defaultPrevented); event.preventDefault() })
      JS

      find("label", text: "Choose a photo").click
      assert_equal [ true ], evaluate_script("window.pickerClicks"), "the label's click reaches the file input on #{path}"

      click_label = "[...document.querySelectorAll('label')].find((el) => el.textContent.includes('Choose a photo')).click()"
      execute_script "#{click_label}; #{click_label}"
      assert_equal [ true ], evaluate_script("window.pickerClicks"), "repeat taps inside the window never reach the picker"

      sleep 1 # past the 800 ms window
      execute_script click_label
      assert_equal [ true, true ], evaluate_script("window.pickerClicks"), "a later tap opens it again"
    end
  end

  test "gate messages" do
    visit privacy_path
    cases = {
      "Try a photo of just you" => FaceResults.result(FaceResults.face(centre: [ 0.3, 0.5 ], width: 0.3), FaceResults.face(centre: [ 0.7, 0.5 ], width: 0.3)),
      "Open your eyes wide" => FaceResults.result(FaceResults.face(eyeBlinkLeft: 0.9, eyeBlinkRight: 0.85)),
      "Look straight at the phone" => FaceResults.result(FaceResults.face(yaw: 20)),
      "Come a little closer" => FaceResults.result(FaceResults.face(width: 0.15)),
      "Step back a little" => FaceResults.result(FaceResults.face(width: 0.75)),
      "Hold still" => FaceResults.result(FaceResults.face(jawOpen: 0.6))
    }
    cases["Look straight at the phone (no face)"] = { faceLandmarks: [] }
    cases["Look straight at the phone (nodding)"] = FaceResults.result(FaceResults.face(pitch: -15))
    cases["Open your eyes wide (squinting)"] = FaceResults.result(FaceResults.face(eyeSquintRight: 0.5))

    verdicts = evaluate_async_script(<<~JS, cases.values, FaceResults.result(FaceResults.face))
      const [results, good, done] = arguments
      import("capture/gate").then((gate) => done({ messages: results.map((result) => gate.evaluate(result).message), good: gate.evaluate(good) }))
    JS

    assert_equal cases.keys.map { |key| key.sub(/ \(.*\)\z/, "") }, verdicts["messages"]
    assert_equal({ "ok" => true }, verdicts["good"])
  end

  test "sampler returns lip colour" do
    visit privacy_path
    sampled = evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("capture/sampler").then((sampler) => {
        const canvas = document.createElement("canvas")
        canvas.width = 400
        canvas.height = 500
        const context = canvas.getContext("2d")
        context.fillStyle = "#C99A7A" // skin
        context.fillRect(0, 0, 400, 500)
        context.fillStyle = "#A84452" // lips
        context.fillRect(150, 350, 100, 40)
        // A face 0.2 to 0.8 wide; lip points inside the painted lips, forehead points on skin.
        const landmarks = Array.from({ length: 478 }, (_, i) => ({ x: 0.2 + 0.6 * (i % 2), y: 0.4 }))
        const lipPoints = [0, 13, 37, 82, 267, 312, 40, 80, 270, 310, 17, 14, 84, 87, 314, 317, 91, 88, 321, 318]
        lipPoints.forEach((index, n) => { landmarks[index] = { x: 0.42 + 0.16 * (n % 5) / 4, y: 0.715 + 0.03 * (n % 2) } })
        ;[151, 108, 337, 9].forEach((index) => { landmarks[index] = { x: 0.5, y: 0.2 } })
        const imageData = context.getImageData(0, 0, 400, 500)
        done({ colours: sampler.sampleRegions(imageData, landmarks, ["lips", "skin"]), size: sampler.uploadSize(1280, 1920) })
      })
    JS

    assert_operator delta_e(sampled["colours"]["lips"], "#A84452"), :<, 10
    assert_operator delta_e(sampled["colours"]["skin"], "#C99A7A"), :<, 10
    assert_equal 0, sampled["size"]["width"] % 8
    assert_operator sampled["size"]["height"], :<, 1080
  end

  private
    def wait_for_guard
      page.document.synchronize(5) do
        connected = evaluate_script("!!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('input[data-capture-target=choose]'), 'tap-guard')")
        raise Capybara::ExpectationNotMet, "tap-guard not connected" unless connected
      end
    end

    def on_phone
      page.current_window.resize_to(390, 844)
      yield
    end

    teardown { page.current_window.resize_to(1400, 1400) }

    # CIE76 colour difference between two "#RRGGBB" colours.
    def delta_e(one, other)
      Math.sqrt(lab(one).zip(lab(other)).sum { |a, b| (a - b)**2 })
    end

    def lab(hex)
      r, g, b = hex.delete("#").scan(/../).map { |pair| pair.to_i(16) / 255.0 }.map { |c| c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
      x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
      y = 0.2126729 * r + 0.7151522 * g + 0.072175 * b
      z = (0.0193339 * r + 0.119192 * g + 0.9503041 * b) / 1.08883
      f = ->(t) { t > 216.0 / 24_389 ? Math.cbrt(t) : (24_389.0 / 27 * t + 16) / 116 }
      [ 116 * f.(y) - 16, 500 * (f.(x) - f.(y)), 200 * (f.(y) - f.(z)) ]
    end
end
