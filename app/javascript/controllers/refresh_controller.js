import { Controller } from "@hotwired/stimulus"

// A fallback for the live update. While a preview on the page is on its way (pending or running), the page reloads
// itself in place every 20 s, in case the live connection that swaps in each result isn't there. It stops when none
// is left, and gives up 10 minutes after it began for this address. A reload is a GET: it never makes a preview or
// spends units. Only previews already asked for count, not the stand-ins shown before the page asks.
const EVERY_MS = 20_000
const GIVE_UP_MS = 10 * 60_000
const WORKING = '.render--pending[id^="render_"], .render--running[id^="render_"]'
// When each address began waiting. Lives in the module, so it outlives the reloads (Turbo visits).
const waitingSince = new Map()

export default class extends Controller {
  connect() {
    if (!this.working) {
      waitingSince.delete(location.href)
      return
    }
    if (!waitingSince.has(location.href)) waitingSince.set(location.href, Date.now())
    this.timer = setTimeout(() => this.refresh(), EVERY_MS)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.timer = null
  }

  refresh() {
    this.timer = null
    if (!this.working) {
      waitingSince.delete(location.href)
      return
    }
    if (Date.now() - waitingSince.get(location.href) > GIVE_UP_MS) return
    window.Turbo.visit(location.href, { action: "replace" })
  }

  get working() {
    return this.element.querySelector(WORKING) !== null
  }
}
