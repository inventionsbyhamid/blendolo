import { Controller } from "@hotwired/stimulus"

// Classic and easy side by side, or one at a time with big toggle buttons. No slider and no drag.
export default class extends Controller {
  static targets = ["stage", "toggles"]

  connect() {
    this.togglesTarget.hidden = false
  }

  show({ params: { show } }) {
    this.stageTarget.dataset.show = show
    this.togglesTarget.querySelectorAll("[aria-pressed]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.compareShowParam === show))
    })
  }
}
