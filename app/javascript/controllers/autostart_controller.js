import { Controller } from "@hotwired/stimulus"

// Sends its form once when the page shows, so the previews start without a tap (the button stays for when they
// don't). It never sends twice for the same page within a minute, so a failed start can't loop.
const ONCE_MS = 60_000

export default class extends Controller {
  connect() {
    const key = `blendolo:autostart:${this.element.action}`
    let last = 0
    try { last = Number(sessionStorage.getItem(key)) || 0 } catch {}
    if (Date.now() - last < ONCE_MS) return
    try { sessionStorage.setItem(key, String(Date.now())) } catch {}
    this.element.requestSubmit()
  }
}
