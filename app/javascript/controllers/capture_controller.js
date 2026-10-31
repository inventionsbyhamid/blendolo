import { Controller } from "@hotwired/stimulus"
import { evaluate, movement, loadLandmarker, LIMITS, MESSAGES } from "capture/gate"
import { sampleRegions, sharpness, toJpeg, pixels } from "capture/sampler"

// Hands-free photo. The phone stands on its own; the camera checks each frame (one face, close enough, looking
// straight, eyes open) and takes the photo by itself after a second of stillness: a burst of five frames, keeping the
// sharpest. There's always a big shutter, 3 and 10 second timers, "Choose a photo", and "A helper is taking it".
// Messages are shown large and, unless switched off, spoken. Everything happens on this one page: the chosen photo
// is re-encoded (JPEG, width a multiple of 8, height under 1080), its colours sampled, and sent with the form.
const BURST = 5
const BURST_GAP_MS = 150
const DETECT_EVERY_MS = 100
const SAY_AGAIN_AFTER_MS = 4000
// A new check message shows (and is spoken) only after it has held this long, so a head near a limit doesn't make
// the words flicker between two messages.
const HOLD_MS = 600
// How long "Choose a photo" waits for the face checks to load before going on without them.
const CHECKS_WAIT_MS = 8000
const SPEECH_KEY = "blendolo:spoken-help"

export default class extends Controller {
  static targets = ["video", "message", "count", "review", "reviewImage", "form", "file", "sampled", "source",
    "choose", "speech", "helper", "liveControls"]
  static values = { packageUrl: String, modelUrl: String, regions: Array, camera: { type: Boolean, default: true },
    choosePrompt: String }

  connect() {
    this.attempt = 0
    this.spoken = this.readSpokenSetting()
    this.facing = "user"
    this.renderSpeech()
    this.loadGates()
    this.leave = () => this.stopCamera()
    // Back from another site restores this page from the browser's cache with the camera off: start it again.
    this.restore = (event) => {
      if (event.persisted && this.cameraValue && this.state !== "review") this.startCamera()
    }
    document.addEventListener("turbo:before-visit", this.leave)
    window.addEventListener("pagehide", this.leave)
    window.addEventListener("pageshow", this.restore)
    this.fresh()
  }

  disconnect() {
    this.attempt += 1
    this.stopCamera()
    document.removeEventListener("turbo:before-visit", this.leave)
    window.removeEventListener("pagehide", this.leave)
    window.removeEventListener("pageshow", this.restore)
    clearTimeout(this.countdownTimer)
    window.speechSynthesis?.cancel()
  }

  // The camera running (or "Choose a photo" for an old photo), nothing chosen.
  fresh() {
    this.reviewTarget.hidden = true
    this.liveControlsTarget.hidden = false
    this.chooseTarget.value = ""
    this.pending = null
    if (this.cameraValue) {
      this.startCamera()
    } else {
      this.state = "choose"
      this.say(this.choosePromptValue)
    }
  }

  // Camera -------------------------------------------------------------------------------------------------------

  // Starts the camera. Only the latest start counts: a stream that arrives after another start, or after leaving the
  // page (say during the permission prompt), is stopped at once, so the camera light never stays on.
  async startCamera() {
    this.stopCamera()
    if (!navigator.mediaDevices?.getUserMedia) return this.noCamera()
    const attempt = ++this.attempt

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: this.facing, width: { ideal: 1280 }, height: { ideal: 1280 } }, audio: false
      })
      if (attempt !== this.attempt || !this.element.isConnected) {
        stream.getTracks().forEach((track) => track.stop())
        return
      }
      this.stream = stream
      this.videoTarget.srcObject = this.stream
      this.videoTarget.classList.toggle("capture__video--mirror", this.facing === "user")
      await this.videoTarget.play()
      this.state = "live"
      this.say(this.gate ? MESSAGES.straight : "Tap Take the photo when you're ready")
      this.loop()
    } catch {
      if (attempt === this.attempt) this.noCamera()
    }
  }

  stopCamera() {
    cancelAnimationFrame(this.frame)
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
    if (this.videoTarget) this.videoTarget.srcObject = null
  }

  noCamera() {
    this.state = "no-camera"
    this.show("We can't use the camera here. Choose a photo instead.")
  }

  async loadGates() {
    if (!this.packageUrlValue || !this.modelUrlValue) return
    this.gatesLoading = loadLandmarker(this.packageUrlValue, this.modelUrlValue)
    try {
      this.gate = await this.gatesLoading
    } catch {
      this.gate = null // No checks: the shutter, the timers and "Choose a photo" still work.
    }
  }

  // Each frame: check the gates, and take the photo after a second of stillness.
  loop() {
    this.frame = requestAnimationFrame((now) => {
      if (this.state !== "live") return
      if (this.gate && this.videoTarget.readyState >= 2 && now - (this.lastDetect || 0) >= DETECT_EVERY_MS && !this.counting) {
        this.lastDetect = now
        this.check(now)
      }
      this.loop()
    })
  }

  check(now) {
    let result
    try {
      result = this.gate.detectForVideo(this.videoTarget, now)
    } catch {
      return
    }
    const verdict = evaluate(result)
    const landmarks = result.faceLandmarks?.[0]
    const moved = movement(this.lastLandmarks, landmarks)
    this.lastLandmarks = landmarks

    if (!verdict.ok) {
      this.stillSince = null
      return this.propose(verdict.message, now)
    }
    if (moved > LIMITS.maxMove || !this.stillSince) {
      this.stillSince = moved > LIMITS.maxMove ? null : now
      return this.propose(MESSAGES.still, now)
    }
    if (now - this.stillSince >= LIMITS.stillFor) this.burst()
  }

  // Five frames, keep the sharpest: a shake during the second of stillness doesn't blur the photo.
  async burst() {
    if (this.state !== "live") return
    this.state = "taking"
    let best = null
    for (let i = 0; i < BURST; i++) {
      const canvas = document.createElement("canvas")
      canvas.width = this.videoTarget.videoWidth
      canvas.height = this.videoTarget.videoHeight
      canvas.getContext("2d").drawImage(this.videoTarget, 0, 0)
      const score = sharpness(canvas)
      if (!best || score > best.score) best = { canvas, score }
      await new Promise((resolve) => setTimeout(resolve, BURST_GAP_MS))
    }
    this.say(MESSAGES.done)
    this.stopCamera()
    await this.review(best.canvas, "camera")
  }

  // Buttons ------------------------------------------------------------------------------------------------------

  shoot() {
    if (this.state === "live") this.burst()
  }

  timer({ params: { seconds } }) {
    if (this.state !== "live" || this.counting) return
    this.counting = true
    let left = seconds
    const tick = () => {
      if (left === 0) {
        this.counting = false
        this.countTarget.textContent = ""
        return this.burst()
      }
      this.countTarget.textContent = left
      this.say(String(left), { force: true })
      left -= 1
      this.countdownTimer = setTimeout(tick, 1000)
    }
    tick()
  }

  helper() {
    this.facing = this.facing === "user" ? "environment" : "user"
    const helping = this.facing === "environment"
    this.helperTarget.setAttribute("aria-pressed", String(helping))
    this.helperTarget.querySelector(".btn__label").textContent = helping ? "I'm taking it myself" : "A helper is taking it"
    this.startCamera()
  }

  toggleSpeech() {
    this.spoken = !this.spoken
    try { localStorage.setItem(SPEECH_KEY, this.spoken ? "on" : "off") } catch {}
    if (!this.spoken) window.speechSynthesis?.cancel()
    this.renderSpeech()
  }

  // "Choose a photo": check it has one face, sample its colours, re-encode, then show it to confirm. A photo that
  // can't be used says why and leaves the camera (or "Choose a photo") ready for another go.
  async choose() {
    const file = this.chooseTarget.files[0]
    if (!file) return
    this.stopCamera()
    this.say("Checking the photo")
    const image = new Image()
    image.src = URL.createObjectURL(file)
    try {
      await image.decode()
    } catch {
      // A format this browser can't show (HEIC outside Safari): send it as it is; the server converts it.
      return this.send(file, {}, "upload")
    }
    const faces = await this.detectStill(image)
    if (faces && faces.length !== 1) {
      const message = faces.length > 1 ? MESSAGES.manyFaces : "We couldn't find a face in that photo. Please choose another."
      this.fresh()
      return this.say(message, { force: true })
    }
    await this.review(image, "upload", faces?.[0])
  }

  again() {
    this.fresh()
  }

  // Review and send ----------------------------------------------------------------------------------------------

  async review(source, origin, landmarks) {
    landmarks ||= (await this.detectStill(source))?.[0]
    const sampled = landmarks ? sampleRegions(pixels(source), landmarks, this.regionsValue) : {}
    const blob = await toJpeg(source)
    this.reviewImageTarget.src = URL.createObjectURL(blob)
    this.pending = { blob, sampled, origin }
    this.liveControlsTarget.hidden = true
    this.reviewTarget.hidden = false
    this.state = "review"
    this.show("Is this photo all right?")
    this.messageTarget.scrollIntoView({ block: "start" })
  }

  // "Use this photo": the photo goes in the form's file field, so the normal form (and its repeat-tap guard) sends it.
  usePhoto(event) {
    if (!this.pending) return
    const { blob, sampled, origin } = this.pending
    this.fill(new File([blob], "photo.jpg", { type: "image/jpeg" }), sampled, origin)
    if (!this.fileTarget.files.length) event.preventDefault()
  }

  send(file, sampled, origin) {
    this.fill(file, sampled, origin)
    this.formTarget.requestSubmit()
  }

  fill(file, sampled, origin) {
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileTarget.files = transfer.files
    this.sampledTarget.value = JSON.stringify(sampled)
    this.sourceTarget.value = origin
  }

  // Helpers ------------------------------------------------------------------------------------------------------

  // Face landmarks of a still image, or null when the checks aren't there (or take more than 8 s to load).
  async detectStill(source) {
    if (this.gatesLoading) {
      await Promise.race([this.gatesLoading.catch(() => {}), new Promise((resolve) => setTimeout(resolve, CHECKS_WAIT_MS))])
    }
    if (!this.gate) return null
    try {
      await this.gate.setOptions({ runningMode: "IMAGE" })
      return this.gate.detect(source).faceLandmarks || []
    } catch {
      return null
    } finally {
      await this.gate.setOptions({ runningMode: "VIDEO" }).catch(() => {})
    }
  }

  // A check's message: shown (and spoken) once it has held for HOLD_MS, so it doesn't flicker near a limit.
  propose(message, now) {
    if (message === this.messageTarget.textContent) {
      this.candidate = null
      return
    }
    if (this.candidate !== message) {
      this.candidate = message
      this.candidateSince = now
      return
    }
    if (now - this.candidateSince >= HOLD_MS) {
      this.candidate = null
      this.say(message)
    }
  }

  // Shows a message and speaks it. A message being spoken is never cut off: the newest one waits and is spoken
  // when it ends. force (the countdown, a rejected photo) speaks at once.
  say(message, { force = false } = {}) {
    this.show(message)
    const speech = window.speechSynthesis
    if (!this.spoken || !speech) return
    const now = Date.now()
    if (!force && message === this.lastSpoken && now - this.lastSpokenAt < SAY_AGAIN_AFTER_MS) return
    if (!force && speech.speaking) {
      this.queued = message
      return
    }
    this.queued = null
    this.lastSpoken = message
    this.lastSpokenAt = now
    if (force) speech.cancel()
    const utterance = new SpeechSynthesisUtterance(message)
    utterance.rate = 0.9
    utterance.onend = () => {
      const next = this.queued
      this.queued = null
      if (next && next !== this.lastSpoken && next === this.messageTarget.textContent) this.say(next)
    }
    speech.speak(utterance)
  }

  show(message) {
    if (this.messageTarget.textContent !== message) this.messageTarget.textContent = message
  }

  renderSpeech() {
    this.speechTarget.setAttribute("aria-pressed", String(this.spoken))
    this.speechTarget.querySelector(".btn__label").textContent = this.spoken ? "Spoken help: on" : "Spoken help: off"
  }

  readSpokenSetting() {
    try { return localStorage.getItem(SPEECH_KEY) !== "off" } catch { return true }
  }

  set state(value) {
    this.element.dataset.captureState = value
  }

  get state() {
    return this.element.dataset.captureState
  }
}
