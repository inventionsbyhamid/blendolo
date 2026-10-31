import { Controller } from "@hotwired/stimulus"
import { evaluate, movement, LIMITS, MESSAGES } from "capture/gate"
import { startChecks } from "capture/checks"
import { sampleRegions, sharpness, toJpeg, pixels } from "capture/sampler"

// Hands-free photo. The phone stands on its own; a few times a second the page checks the camera's picture (one face,
// close enough, looking straight, eyes open) and takes the photo by itself after a second of stillness: a burst of
// five frames, keeping the sharpest. The checks run in a worker where the browser allows it (capture/checks.js), so
// the page stays quick to answer taps. There's always a big shutter, 3 and 10 second timers, "Choose a photo", and
// "A helper is taking it". Messages are shown large and, unless switched off, spoken. Everything happens on this one
// page: the chosen photo is re-encoded (JPEG, width a multiple of 8, height under 1080), its colours sampled, and sent
// with the form.
const BURST = 5
const BURST_GAP_MS = 150
// After each check the next waits at least this long, and at least this many times as long as the check took, so the
// checks never take more than half the time (a third when the page runs them itself, without a worker).
const CHECK_GAP_MS = { worker: 200, page: 300 }
const CHECK_SHARE = { worker: 2, page: 3 }
// After this many checks in a row that fail or get an empty frame, the checks give way: the worker to the page's own
// checks, those to the shutter and timers alone (giveWay).
const MISSES_TO_GIVE_WAY = 10
const NO_CHECKS = "Tap Take the photo when you're ready"
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
  static values = { packageUrl: String, modelUrl: String, workerUrl: String, gateUrl: String, regions: Array,
    camera: { type: Boolean, default: true }, choosePrompt: String }

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
    // The checks rest while the page is hidden (another tab, the phone locked) and start afresh when it shows again.
    this.visibility = () => {
      this.lastPoints = null
      this.watch()
    }
    document.addEventListener("turbo:before-visit", this.leave)
    document.addEventListener("visibilitychange", this.visibility)
    window.addEventListener("pagehide", this.leave)
    window.addEventListener("pageshow", this.restore)
    this.fresh()
  }

  disconnect() {
    this.attempt += 1
    this.stopCamera()
    document.removeEventListener("turbo:before-visit", this.leave)
    document.removeEventListener("visibilitychange", this.visibility)
    window.removeEventListener("pagehide", this.leave)
    window.removeEventListener("pageshow", this.restore)
    clearTimeout(this.countdownTimer)
    window.speechSynthesis?.cancel()
    this.gatesLoading = null
    this.gate?.close()
    this.gate = null
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
      this.say(this.gate ? MESSAGES.straight : NO_CHECKS)
      this.lastPoints = null
      this.misses = 0
      this.watch()
    } catch {
      if (attempt === this.attempt) this.noCamera()
    }
  }

  stopCamera() {
    clearTimeout(this.watchTimer)
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
    if (this.videoTarget) this.videoTarget.srcObject = null
  }

  noCamera() {
    this.state = "no-camera"
    this.show("We can't use the camera here. Choose a photo instead.")
  }

  // Starts loading the face checks as the page opens, so they're ready by the time the camera shows. worker: false
  // loads the page's own checks, after the worker gave way.
  async loadGates({ worker = true } = {}) {
    if (!this.packageUrlValue || !this.modelUrlValue) return
    const loading = startChecks({ packageUrl: this.packageUrlValue, modelUrl: this.modelUrlValue,
      workerUrl: worker ? this.workerUrlValue : "", gateUrl: this.gateUrlValue })
    this.gatesLoading = loading
    let gate = null
    try {
      gate = await loading
    } catch {
      // No checks: the shutter, the timers and "Choose a photo" still work.
    }
    if (this.gatesLoading !== loading) return gate?.close() // The page was left meanwhile.
    this.gate = gate
    if (gate) this.watch()
    else if (!worker && this.state === "live") this.say(NO_CHECKS)
  }

  // The checks failed for good (a worker that stopped), or kept failing or getting empty frames (a camera or browser
  // fault): close them. The worker gives way to the page's own checks; when those fail too, the checks stop and the
  // page says to use the shutter.
  giveWay(gate) {
    gate.close()
    this.gate = null
    this.misses = 0
    if (gate.kind === "worker") return this.loadGates({ worker: false })
    this.gatesLoading = null
    if (this.state === "live") this.say(NO_CHECKS)
  }

  // While the camera is live: check a frame, wait (CHECK_GAP_MS), check the next. One frame at a time, never during
  // the countdown, the burst or the review, or while the page is hidden.
  watch(delay = 0) {
    clearTimeout(this.watchTimer)
    if (this.watching) this.watchTimer = setTimeout(() => this.look(), delay)
  }

  get watching() {
    return this.state === "live" && this.gate && !this.counting && !document.hidden
  }

  async look() {
    const gate = this.gate
    if (!this.watching) return
    if (this.videoTarget.readyState < 2) return this.watch(CHECK_GAP_MS[gate.kind])
    const attempt = this.attempt
    const started = performance.now()
    let summary = null
    let failed = false
    try {
      summary = await gate.video(this.videoTarget, started)
    } catch {
      failed = true // This frame couldn't be checked; the next one may be.
    }
    if (attempt !== this.attempt || gate !== this.gate || !this.watching) return
    if (gate.broken) return this.giveWay(gate)
    if (failed || summary?.blank) this.misses += 1
    else if (summary) this.misses = 0
    if (this.misses >= MISSES_TO_GIVE_WAY) return this.giveWay(gate)
    if (summary) this.check(summary, started)
    const took = performance.now() - started
    this.watch(Math.max(CHECK_GAP_MS[gate.kind], CHECK_SHARE[gate.kind] * took) - took)
  }

  // One frame's checks: say what to change, or take the photo after a second of stillness.
  check(summary, now) {
    const verdict = evaluate(summary)
    const moved = movement(this.lastPoints, summary.points, now - this.lastCheckAt)
    this.lastPoints = summary.points
    this.lastCheckAt = now
    // Since when the face has held still, alone and facing the phone, with nothing wrong but perhaps the eyes.
    const steady = (verdict.ok || verdict.eyesOnly) && moved <= LIMITS.maxMove
    this.steadySince = steady ? (this.steadySince ?? now) : null

    if (!verdict.ok) {
      this.stillSince = null
      // Smiling and older eyes can read as closed: after holding still a while, the photo is taken anyway, saying so.
      if (steady && now - this.steadySince >= LIMITS.eyesWaitFor) return this.burst(MESSAGES.doneEyes)
      return this.propose(verdict.message, now)
    }
    if (moved > LIMITS.maxMove || !this.stillSince) {
      this.stillSince = moved > LIMITS.maxMove ? null : now
      return this.propose(MESSAGES.still, now)
    }
    if (now - this.stillSince >= LIMITS.stillFor) this.burst()
  }

  // Five frames, keep the sharpest: a shake during the second of stillness doesn't blur the photo. message: what to
  // say once taken, kept on the review screen when it's more than "Got it".
  async burst(message = MESSAGES.done) {
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
    this.say(message)
    this.stopCamera()
    await this.review(best.canvas, "camera")
    if (message !== MESSAGES.done) this.show(`${message} Is this photo all right?`)
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
    this.reviewImage.src = URL.createObjectURL(blob)
    this.pending = { blob, sampled, origin }
    this.liveControlsTarget.hidden = true
    this.reviewTarget.hidden = false
    this.state = "review"
    this.show("Is this photo all right?")
    this.messageTarget.scrollIntoView({ block: "start" })
  }

  // The picture on the review screen, made the first time there's a photo (an <img> without a src isn't valid).
  get reviewImage() {
    if (this.hasReviewImageTarget) return this.reviewImageTarget
    const image = document.createElement("img")
    image.className = "capture__review"
    image.alt = "The photo you just took"
    image.dataset.captureTarget = "reviewImage"
    this.reviewTarget.prepend(image)
    return image
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
      return await this.gate.still(source)
    } catch {
      return null
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
