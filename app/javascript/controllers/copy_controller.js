import { Controller } from "@hotwired/stimulus"

// "Copy the link": one tap copies the private link. The text box stays, for phones without clipboard access.
export default class extends Controller {
  static targets = ["source", "button", "label"]

  connect() {
    if (navigator.clipboard) this.buttonTarget.hidden = false
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
      this.labelTarget.textContent = "Copied"
    } catch {
      this.sourceTarget.select()
      this.labelTarget.textContent = "Select the link above and copy it"
    }
  }
}
