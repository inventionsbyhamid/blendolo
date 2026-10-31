import { Controller } from "@hotwired/stimulus"

// "Read it to me": reads the step card aloud with the phone's own voice (Web Speech), a little slower than usual.
// Tapping again stops it.
export default class extends Controller {
  static targets = ["text", "button", "label", "status"]

  disconnect() {
    window.speechSynthesis?.cancel()
  }

  toggle() {
    const speech = window.speechSynthesis
    if (!speech) {
      this.statusTarget.textContent = "Read aloud isn't available in this browser."
      return
    }
    if (speech.speaking) {
      speech.cancel()
      return this.stopped()
    }

    const utterance = new SpeechSynthesisUtterance(this.textTargets.map((element) => element.textContent.trim()).join(". "))
    utterance.rate = 0.9
    utterance.onend = utterance.onerror = () => this.stopped()
    speech.cancel()
    speech.speak(utterance)
    this.labelTarget.textContent = "Stop reading"
    this.buttonTarget.setAttribute("aria-pressed", "true")
  }

  stopped() {
    this.labelTarget.textContent = "Read it to me"
    this.buttonTarget.setAttribute("aria-pressed", "false")
  }
}
