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

  test "checks that keep failing give way to the page's, then the shutter, until the camera starts again" do
    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=live]", wait: 10
    # A worker whose copies of the frames come out empty, and page checks that fail on every camera frame but still
    # check a chosen photo (they find no face in it).
    execute_script <<~JS
      #{FAKE_CHECKS}
      window.log = []
      const capture = captureController()
      const worker = fakeChecks("worker", async () => ({ ...noFace, blank: true }))
      const page = fakeChecks("page", async () => { throw new Error("lost") })
      capture.loadGates = async ({ worker = true } = {}) => {
        log.push(worker ? "load worker checks" : "load page checks")
        capture.gate = page
        capture.watch()
      }
      const message = document.querySelector("[data-capture-target=message]")
      window.shown = []
      new MutationObserver(() => window.shown.push(message.textContent))
        .observe(message, { childList: true, characterData: true, subtree: true })
      capture.show("Look straight at the phone")
      capture.gate = worker
      capture.watch()
    JS

    assert_selector "[data-capture-target=message]", text: "Tap Take the photo when you're ready", wait: 15
    assert_equal [ "worker closed", "load page checks" ], evaluate_script("window.log")
    assert_equal "page", evaluate_script("captureController().gate.kind"), "kept for a chosen photo"

    # "Choose a photo" still checks its photo; turning it down starts the camera again, and the checks afresh.
    find("input[data-capture-target=choose]", visible: :all).attach_file(file_fixture("face.jpg"))
    assert_selector "[data-capture-state=live]", wait: 10
    assert_includes evaluate_script("window.shown"), "We couldn't find a face in that photo. Please choose another."
    assert_equal [ "worker closed", "load page checks", "page closed", "load worker checks" ], evaluate_script("window.log").first(4)
    click_on "Take the photo"
    assert_selector "[data-capture-state=review]", wait: 10
  end

  test "a stopped worker gives way before a chosen photo is checked" do
    visit new_kit_photo_path(@kit, kind: "reference")
    assert_selector "[data-capture-state=choose]", wait: 10
    two_faces = FaceResults.result(FaceResults.face(centre: [ 0.3, 0.5 ], width: 0.3), FaceResults.face(centre: [ 0.7, 0.5 ], width: 0.3))
    execute_script <<~JS, two_faces[:faceLandmarks]
      const faces = arguments[0]
      #{FAKE_CHECKS}
      window.log = []
      const capture = captureController()
      const worker = fakeChecks("worker", async () => noFace)
      worker.broken = new Error("The face checks stopped answering")
      capture.loadGates = async () => {
        log.push("load page checks")
        capture.gate = { ...fakeChecks("page", async () => noFace), still: async () => faces }
      }
      capture.gate = worker
    JS

    find("input[data-capture-target=choose]", visible: :all).attach_file(file_fixture("face.jpg"))
    assert_selector "[data-capture-target=message]", text: "Try a photo of just you", wait: 10
    assert_equal [ "worker closed", "load page checks" ], evaluate_script("window.log")
  end

  test "a worker that stops after starting gives way at once, and no face in view isn't a failure" do
    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=live]", wait: 10
    execute_script <<~JS
      #{FAKE_CHECKS}
      window.log = []
      const capture = captureController()
      const page = fakeChecks("page", async () => noFace)
      capture.loadGates = async () => {
        log.push("load page checks")
        capture.gate = page
        capture.watch()
      }
      const worker = fakeChecks("worker", async () => {
        worker.broken = new Error("The face checks stopped")
        throw worker.broken
      })
      capture.gate = worker
      capture.watch()
    JS

    page.document.synchronize(3) do
      raise Capybara::ExpectationNotMet, "worker still in use" unless evaluate_script("window.log.length") == 2
    end
    assert_equal [ "worker closed", "load page checks" ], evaluate_script("window.log")
    sleep 4 # well past ten checks of the page's, each finding no face in a real picture
    assert_equal [ "worker closed", "load page checks" ], evaluate_script("window.log")
    assert_equal "page", evaluate_script("captureController().gate.kind")
  end

  test "a worker that doesn't answer is stopped, and the photo goes on without colours" do
    visit privacy_path
    outcome = using_wait_time(15) do
      evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        import("capture/checks").then(async ({ WorkerChecks }) => {
          const log = []
          const checks = new WorkerChecks({ postMessage: (message) => log.push(message.type), terminate: () => log.push("terminated") })
          const photo = document.createElement("canvas")
          photo.width = photo.height = 8
          const started = performance.now()
          const answer = await checks.still(photo).then(() => "answered", (error) => error.message)
          done({ answer, waited: performance.now() - started, broken: !!checks.broken, log })
        })
      JS
    end

    assert_equal "The face checks stopped answering", outcome["answer"]
    assert_in_delta 5000, outcome["waited"], 1000
    assert outcome["broken"]
    assert_equal [ "still", "terminated" ], outcome["log"]
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
    cases["Open your eyes wide (squinting hard)"] = FaceResults.result(FaceResults.face(eyeSquintRight: 0.8))
    good = {
      straight: FaceResults.result(FaceResults.face),
      smiling: FaceResults.result(FaceResults.face(eyeSquintLeft: 0.6, eyeSquintRight: 0.7, eyeBlinkLeft: 0.25, eyeBlinkRight: 0.2))
    }
    eyes = {
      closed: FaceResults.result(FaceResults.face(eyeBlinkLeft: 0.7, eyeBlinkRight: 0.65)),
      closed_mouth_open: FaceResults.result(FaceResults.face(eyeBlinkLeft: 0.7, eyeBlinkRight: 0.65, jawOpen: 0.6)),
      shut: FaceResults.result(FaceResults.face(eyeBlinkLeft: 0.9, eyeBlinkRight: 0.8)),
      one_shut: FaceResults.result(FaceResults.face(eyeBlinkLeft: 0.9, eyeBlinkRight: 0.3))
    }

    verdicts = evaluate_async_script(<<~JS, cases.values, good, eyes)
      const [results, good, eyes, done] = arguments
      import("capture/gate").then((gate) => {
        const evaluate = (result) => gate.evaluate(gate.summarize(result))
        const each = (results) => Object.fromEntries(Object.entries(results).map(([name, result]) => [name, evaluate(result)]))
        done({ messages: results.map((result) => evaluate(result).message), good: each(good), eyes: each(eyes) })
      })
    JS

    assert_equal cases.keys.map { |key| key.sub(/ \(.*\)\z/, "") }, verdicts["messages"]
    assert_equal({ "ok" => true }, verdicts["good"]["straight"])
    assert_equal({ "ok" => true }, verdicts["good"]["smiling"], "smiling eyes read as squinting, and pass")
    assert_equal({ "ok" => false, "message" => "Open your eyes wide", "eyesOnly" => true }, verdicts["eyes"]["closed"])
    assert_equal false, verdicts["eyes"]["closed_mouth_open"]["eyesOnly"], "the eyes aren't the only problem"
    assert_equal({ "ok" => false, "message" => "Open your eyes wide", "eyesOnly" => false }, verdicts["eyes"]["shut"])
    assert_equal true, verdicts["eyes"]["one_shut"]["eyesOnly"], "one eye shut is a wink or a droopy lid"
  end

  test "a still face whose only problem is the eyes is taken after 4 seconds, saying so" do
    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=live]", wait: 10
    closed = { eyeBlinkLeft: 0.7, eyeBlinkRight: 0.65 }
    results = [
      FaceResults.result(FaceResults.face(**closed)),
      FaceResults.result(FaceResults.face(centre: [ 0.55, 0.5 ], **closed)),
      FaceResults.result(FaceResults.face(jawOpen: 0.6, **closed)),
      FaceResults.result(FaceResults.face(eyeBlinkLeft: 0.9, eyeBlinkRight: 0.85))
    ]

    # Checks every 200 ms, as the camera would make them.
    states = evaluate_async_script(<<~JS, *results)
      const [closed, closedMoved, closedMouthOpen, shut, done] = arguments
      import("capture/gate").then((gate) => {
        const capture = window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~=capture]"), "capture")
        const message = document.querySelector("[data-capture-target=message]")
        window.shown = []
        new MutationObserver(() => window.shown.push(message.textContent))
          .observe(message, { childList: true, characterData: true, subtree: true })
        const states = {}
        let t = 1000000
        const look = (result, ms) => { for (const end = t + ms; t <= end; t += 200) capture.check(gate.summarize(result), t) }
        look(closedMouthOpen, 5000)
        states.mouthOpen = capture.state
        look(shut, 5000)
        states.shut = capture.state
        for (let i = 0; i <= 25; i++) look(i % 2 ? closedMoved : closed, 0)
        states.moving = capture.state
        look(closed, 3800)
        states.before = capture.state
        states.message = document.querySelector("[data-capture-target=message]").textContent
        look(closed, 400)
        states.after = capture.state
        done(states)
      })
    JS

    assert_equal "live", states["mouthOpen"], "not when the mouth is open too"
    assert_equal "live", states["shut"], "not when the eyes are shut"
    assert_equal "live", states["moving"], "not while the head moves"
    assert_equal "live", states["before"], "not before 4 seconds"
    assert_equal "Open your eyes wide", states["message"]
    assert_equal "taking", states["after"]
    assert_selector "[data-capture-state=review]", wait: 10
    note = "Your eyes looked a little closed, so the preview may show softer liner. Is this photo all right?"
    assert_selector "[data-capture-target=message]", exact_text: note
    shown = evaluate_script("window.shown")
    assert_equal [ "Got it", note ], shown.last(2), "the note reaches the live region once, whole"
    assert_equal 1, shown.count { it.include?("Your eyes") }
  end

  test "stillness is measured per 100 ms" do
    visit privacy_path
    moved = evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("capture/gate").then((gate) => {
        const at = (x) => [0, 1, 2, 3].map(() => ({ x, y: 0.5 }))
        done([gate.movement(at(0.5), at(0.51), 100), gate.movement(at(0.5), at(0.52), 200), gate.movement(at(0.5), at(0.51), 50),
          gate.movement(at(0.5), at(0.52), 1000)])
      })
    JS

    assert_in_delta 0.01, moved[0], 1e-9
    assert_in_delta 0.01, moved[1], 1e-9, "twice as far in twice the time is the same speed"
    assert_in_delta 0.01, moved[2], 1e-9, "checks closer together aren't scaled up"
    assert_in_delta 0.01, moved[3], 1e-9, "a longer gap counts as 200 ms"
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

  # Stand-ins for capture/checks.js, put on the page by the tests above.
  FAKE_CHECKS = <<~JS.freeze
    window.captureController = () =>
      window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("[data-controller~=capture]"), "capture")
    window.noFace = { faces: 0, width: 0, angles: null, points: null,
      scores: { eyeBlinkLeft: 0, eyeBlinkRight: 0, eyeSquintLeft: 0, eyeSquintRight: 0, jawOpen: 0 } }
    window.fakeChecks = (kind, video) => ({ kind, video, still: async () => [], close: () => log.push(`${kind} closed`) })
  JS

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
