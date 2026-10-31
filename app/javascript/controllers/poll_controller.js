import { Controller } from "@hotwired/stimulus"

// Checks again, politely, for something the server is waiting on (credits after paying). On a <turbo-frame>: every
// 4 s it reloads just this frame from the page's own address (a GET, which changes nothing), and stops once the frame
// holds [data-done], after two minutes, or while the device is offline. The words in the frame already say what to
// expect, so nothing depends on this running.
const EVERY_MS = 4_000
const GIVE_UP_MS = 2 * 60_000

export default class extends Controller {
  connect() {
    if (this.done) return
    this.startedAt = Date.now()
    this.timer = setInterval(() => this.check(), EVERY_MS)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  check() {
    if (this.done || Date.now() - this.startedAt > GIVE_UP_MS) {
      clearInterval(this.timer)
      return
    }
    if (!navigator.onLine) return
    if (this.element.src) {
      this.element.reload()
    } else {
      this.element.src = location.href
    }
  }

  get done() {
    return this.element.querySelector("[data-done]") !== null
  }
}
