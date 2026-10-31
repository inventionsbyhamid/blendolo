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
    # The fake camera shows a picture (a test pattern), so the worker's empty copies are the worker's doing.
    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=live]", wait: 10
    # A worker whose copies of the frames come out empty, and page checks that fail on every camera frame but still
    # check a chosen photo (they find no face in it).
    execute_script <<~JS
      #{FAKE_CHECKS}
      window.log = []
      const capture = captureController()
      const worker = fakeChecks("worker", async () => ({ ...noFace, blank: true }))
      window.pageLooks = 0
      const page = fakeChecks("page", async () => {
        pageLooks += 1
        throw new Error("lost")
      })
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
    assert_equal 10, evaluate_script("window.pageLooks")

    # "Choose a photo" still checks its photo; turning it down starts the camera again, and with it the page's checks,
    # without loading anything again (the worker failed once in this visit).
    find("input[data-capture-target=choose]", visible: :all).attach_file(file_fixture("face.jpg"))
    assert_selector "[data-capture-state=live]", wait: 10
    assert_includes evaluate_script("window.shown"), "We couldn't find a face in that photo. Please choose another."
    page.document.synchronize(5) do
      raise Capybara::ExpectationNotMet, "page checks not back" unless evaluate_script("window.pageLooks") > 10
    end
    assert_equal [ "worker closed", "load page checks" ], evaluate_script("window.log")
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

  test "the checks worker's reply wait" do
    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=live]", wait: 10
    outcome = using_wait_time(40) do
      evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        import("capture/checks").then(async ({ WorkerChecks }) => {
          const outcome = {}
          const camera = document.querySelector("video[data-capture-target=video]")
          const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
          const photo = document.createElement("canvas")
          photo.width = photo.height = 8
          // A worker that never answers, and one that answers each frame after a while with the summary given.
          const silent = () => {
            const log = []
            return { log, checks: new WorkerChecks({ postMessage: (message) => log.push(message.type), terminate: () => log.push("terminated") }) }
          }
          const answering = (summary, after = 10) => {
            const checks = new WorkerChecks({
              postMessage: (message) => setTimeout(() => checks.receive({ type: "video", id: message.id, summary: { ...summary } }), after),
              terminate: () => {}
            })
            return checks
          }
          const timed = async (promise) => {
            const started = performance.now()
            const answer = await promise.then(() => "answered", (error) => error.message)
            return { answer, waited: performance.now() - started }
          }
          const noFace = { faces: 0, width: 0, angles: null, points: null, scores: {} }

          // 5 s, or ten times the slowest check, but at most 15 s.
          const { checks } = silent()
          outcome.waits = [ 0, 800, 60000 ].map((slowest) => { checks.slowest = slowest; return checks.replyWait() })

          // No answer to a still photo, and a frame's bitmap that never comes: both stop the worker after 5 s.
          const still = silent()
          const frame = silent()
          const stillWaiting = timed(still.checks.still(photo))
          const makeBitmap = window.createImageBitmap
          window.createImageBitmap = () => new Promise(() => {})
          const frameWaiting = timed(frame.checks.video(camera, 1))
          window.createImageBitmap = makeBitmap
          const [ stillWait, frameWait ] = await Promise.all([ stillWaiting, frameWaiting ])
          Object.assign(outcome, { stillWait, stillLog: still.log, frameWait, frameLog: frame.log, frameBusy: !!frame.checks.busy })

          // Hidden for a moment during the wait (a locked phone): the wait starts again from then.
          let hidden = false
          Object.defineProperty(document, "hidden", { configurable: true, get: () => hidden })
          const asleep = silent()
          const asleepWait = timed(asleep.checks.still(photo))
          await sleep(1000)
          hidden = true
          document.dispatchEvent(new Event("visibilitychange"))
          await sleep(1000)
          hidden = false
          document.dispatchEvent(new Event("visibilitychange"))
          outcome.asleepWait = await asleepWait

          // A check that spanned hidden time doesn't count as the slowest.
          const slow = answering(noFace, 300)
          const check = slow.video(camera, 2)
          await sleep(100)
          document.dispatchEvent(new Event("visibilitychange"))
          await check
          outcome.slowestAfterHidden = slow.slowest
          await slow.video(camera, 3)
          outcome.slowestAwake = slow.slowest
          delete document.hidden

          done(outcome)
        })
      JS
    end

    assert_equal [ 5000, 8000, 15000 ], outcome["waits"]
    assert_equal "The face checks stopped answering", outcome["stillWait"]["answer"]
    assert_in_delta 5000, outcome["stillWait"]["waited"], 1000
    assert_equal [ "still", "terminated" ], outcome["stillLog"]
    assert_equal "The face checks stopped answering", outcome["frameWait"]["answer"], "the wait covers making the bitmap"
    assert_in_delta 5000, outcome["frameWait"]["waited"], 1000
    assert_equal [ "terminated" ], outcome["frameLog"]
    assert_not outcome["frameBusy"]
    assert_equal "The face checks stopped answering", outcome["asleepWait"]["answer"]
    assert_in_delta 10_000, outcome["asleepWait"]["waited"], 1500, "the first wait saw the page hidden, so a second one ran"
    assert_equal 0, outcome["slowestAfterHidden"]
    assert_operator outcome["slowestAwake"], :>=, 250
  end

  test "a dark camera never makes the worker give way" do
    on_phone { visit new_kit_photo_path(@kit) }
    assert_selector "[data-capture-state=live]", wait: 10
    # The phone lies face down: the camera's picture is black, and so is every copy the worker gets.
    evaluate_async_script <<~JS
      const done = arguments[arguments.length - 1]
      #{FAKE_CHECKS}
      window.log = []
      const capture = captureController()
      const dark = document.createElement("canvas")
      dark.width = dark.height = 64
      setInterval(() => dark.getContext("2d").fillRect(0, 0, 64, 64), 50)
      capture.videoTarget.srcObject = dark.captureStream(10)
      capture.videoTarget.play().then(() => {
        window.workerLooks = 0
        capture.gate = fakeChecks("worker", async () => {
          workerLooks += 1
          return { ...noFace, blank: true }
        })
        capture.loadGates = async () => log.push("load page checks")
        capture.watch()
        done()
      })
    JS

    page.document.synchronize(10) do
      raise Capybara::ExpectationNotMet, "too few checks yet" unless evaluate_script("window.workerLooks") >= 25
    end
    assert_equal [], evaluate_script("window.log")
    assert_equal "worker", evaluate_script("captureController().gate.kind")
  end

  test "an empty frame is one with no picture in it" do
    visit privacy_path
    blank = evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("capture/gate").then((gate) => {
        const frame = (paint) => {
          const canvas = document.createElement("canvas")
          canvas.width = 320
          canvas.height = 240
          paint(canvas.getContext("2d"))
          return gate.blankFrame(canvas)
        }
        const fill = (context, colour, x = 0, y = 0, width = 320, height = 240) => {
          context.fillStyle = colour
          context.fillRect(x, y, width, height)
        }
        done({
          black: frame((context) => fill(context, "#000000")),
          grey: frame((context) => fill(context, "#7F7F7F")),
          nearlyBlack: frame((context) => { fill(context, "#050505"); fill(context, "#070707", 0, 0, 160) }),
          face: frame((context) => { fill(context, "#C99A7A"); fill(context, "#3F2A20", 100, 60, 120, 120) }),
          softLight: frame((context) => {
            const light = context.createLinearGradient(0, 0, 320, 0)
            light.addColorStop(0, "#808080")
            light.addColorStop(1, "#909090")
            fill(context, light)
          })
        })
      })
    JS

    assert blank["black"], "a phone lying face down"
    assert blank["grey"]
    assert blank["nearlyBlack"]
    assert_not blank["face"]
    assert_not blank["softLight"], "a plain wall still has a little light and shade"
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

  test "spoken help plays recordings one at a time: the newest message waits, the countdown cuts in at once" do
    visit new_kit_photo_path(@kit)
    assert_selector "[data-capture-state=live]", wait: 10
    result = evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      #{FAKE_CHECKS}
      const tick = () => new Promise((resolve) => setTimeout(resolve, 50))
      import("voice/player").then(async (voice) => {
        const capture = captureController()
        await capture.warmed // the countdown and the commonest prompts, fetched as the page opened
        voice.stopAll() // whatever the page said as the camera started
        const plays = [], sources = [], spoken = []
        let pauses = 0, audio = null
        HTMLAudioElement.prototype.play = function () {
          audio = this
          plays.push(voice.reading())
          sources.push(this.src)
          return Promise.resolve()
        }
        HTMLAudioElement.prototype.pause = function () { pauses += 1 }
        window.speechSynthesis.speak = (utterance) => { spoken.push(utterance.text) }

        capture.say("Hold still")
        capture.say("Step back a little") // waits for "Hold still" to end
        capture.say("Come a little closer") // newer: takes its place
        await tick()
        const whileSaying = { plays: [...plays], pauses }
        audio.dispatchEvent(new Event("ended"))
        await tick()
        const afterEnd = plays.length
        capture.say("3", { force: true }) // cuts "Come a little closer" off
        await tick()
        const afterCountdown = { plays: plays.length, pauses }
        capture.toggleSpeech() // spoken help off: stops it
        const off = capture.element.querySelector("[data-capture-target=speech]").getAttribute("aria-pressed")
        capture.toggleSpeech() // and on again, as the next test expects
        done({ plays, sources, whileSaying, afterEnd, afterCountdown, pauses, spoken, off })
      })
    JS

    assert_equal({ "plays" => [ "Hold still" ], "pauses" => 0 }, result["whileSaying"])
    assert_equal 2, result["afterEnd"], "the newest message is said when the line before ends"
    assert_equal [ "Hold still", "Come a little closer", "3" ], result["plays"]
    held, closer, three = result["sources"]
    assert held.start_with?("blob:"), "fetched ahead: #{held}"
    assert three.start_with?("blob:"), "fetched ahead: #{three}"
    key = Voice.key("Come a little closer")
    assert_equal "/voice/#{key}.mp3?v=#{Voice.manifest.dig(key, "audio")}", URI(closer).request_uri, "from the network"
    assert_equal({ "plays" => 3, "pauses" => 1 }, result["afterCountdown"])
    assert_equal 2, result["pauses"], "switching spoken help off stops the countdown's line"
    assert_empty result["spoken"], "every line had a recording"
    assert_equal "false", result["off"]
  end

  test "spoken help uses the phone's own voice for a message without a recording" do
    visit new_kit_photo_path(@kit)
    assert_selector "[data-capture-state=live]", wait: 10
    spoken = evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      #{FAKE_CHECKS}
      import("voice/player").then(async (voice) => {
        voice.stopAll()
        const spoken = []
        HTMLAudioElement.prototype.play = () => Promise.reject(new Error("no recording should play"))
        window.speechSynthesis.speak = (utterance) => { spoken.push({ text: utterance.text, rate: utterance.rate }) }
        captureController().say("A message nobody recorded")
        await new Promise((resolve) => setTimeout(resolve, 50))
        done(spoken)
      })
    JS

    assert_equal [ "A message nobody recorded" ], spoken.map { |utterance| utterance["text"] }
    assert_in_delta 0.9, spoken.first["rate"], 0.001
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
