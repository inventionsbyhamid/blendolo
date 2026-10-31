import { Controller } from "@hotwired/stimulus"

// Swallows repeat taps. A tremor can turn one tap into two or three: the first click (it fires on release) counts,
// and more clicks inside the window are ignored. A commit control then holds, disabled with a quiet "Working on it",
// until the next page shows. The window follows "My hands today" on <body data-hands>: 500, 800 or 1500 ms.
// The server is repeat-safe too; this keeps a second tap from even being sent.
const WINDOWS = { 0: 500, 1: 800, 2: 1500 }
const DEFAULT_WINDOW = 800

// The last commit tap anywhere in the document. Inside the window after it, every guarded control ignores a tap:
// a bounce onto the neighbouring button, or onto the control in the same place on the next page. It lives in the
// module, so it outlives Turbo visits; a full page load starts afresh.
let lastCommitAt = -Infinity

export default class extends Controller {
  static values = { commit: { type: Boolean, default: true } }

  connect() {
    this.lastAt = -Infinity
    this.release = this.release.bind(this)
    this.failed = this.failed.bind(this)
    document.addEventListener("turbo:before-cache", this.release)
    window.addEventListener("pageshow", this.release)
    this.form?.addEventListener("turbo:submit-end", this.failed)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.release)
    window.removeEventListener("pageshow", this.release)
    this.form?.removeEventListener("turbo:submit-end", this.failed)
  }

  guard(event) {
    const now = performance.now()
    if (this.held || now - this.lastAt < this.window || now - lastCommitAt < this.window) {
      event.preventDefault()
      event.stopImmediatePropagation()
      return
    }
    this.lastAt = now
    if (!this.commitValue) return
    lastCommitAt = now
    if (!this.form || this.form.checkValidity()) this.hold()
  }

  hold() {
    this.held = true
    this.element.classList.add("is-working")
    this.element.setAttribute("aria-busy", "true")
    this.element.setAttribute("aria-disabled", "true")
    // Disabled after this click has started the submit, so the form still sends the button's own name and value.
    if (this.form) setTimeout(() => { this.element.disabled = true })
  }

  release() {
    this.held = false
    this.element.classList.remove("is-working")
    this.element.removeAttribute("aria-busy")
    this.element.removeAttribute("aria-disabled")
    if (this.form) this.element.disabled = false
  }

  // A submit that didn't get through (offline, server down) shouldn't leave the button stuck.
  failed(event) {
    if (!event.detail.success) this.release()
  }

  get form() {
    return this.element.form || null
  }

  get window() {
    return WINDOWS[document.body.dataset.hands] ?? DEFAULT_WINDOW
  }
}
