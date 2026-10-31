import { Controller } from "@hotwired/stimulus"
import * as voice from "voice/player"

// "Read it to me": reads the step card aloud in Blendolo's recorded voice, or the phone's own voice where there's no
// recording (voice/player.js). Tapping again stops it, and so does leaving the page.
export default class extends Controller {
  static targets = ["text", "button", "label", "status"]
  static values = { voices: Object }

  connect() {
    this.stopped()
    // Hashed now, so a tap starts the recording at once, inside the tap (iOS plays sound only from a tap).
    voice.key(this.text)
    this.leave = () => this.stop()
    document.addEventListener("turbo:before-visit", this.leave)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.leave)
    this.stop()
  }

  toggle() {
    if (this.reading) return this.stop()

    this.statusTarget.textContent = ""
    const line = voice.speak(this.text, { voices: this.voicesValue, onend: (reason) => {
      if (this.reading !== line) return
      this.reading = null
      this.stopped()
      if (reason === "unavailable") this.statusTarget.textContent = "Read aloud isn't available in this browser."
    } })
    this.reading = line
    this.labelTarget.textContent = "Stop reading"
    this.buttonTarget.setAttribute("aria-pressed", "true")
  }

  stop() {
    if (this.reading) voice.stop(this.reading)
    this.reading = null
    this.stopped()
  }

  stopped() {
    this.labelTarget.textContent = "Read it to me"
    this.buttonTarget.setAttribute("aria-pressed", "false")
  }

  get text() {
    return voice.joinParts(this.textTargets.map((element) => element.textContent))
  }
}
