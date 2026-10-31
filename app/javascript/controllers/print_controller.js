import { Controller } from "@hotwired/stimulus"

// "Print the cards": the phone's or computer's own print dialog.
export default class extends Controller {
  print() {
    window.print()
  }
}
