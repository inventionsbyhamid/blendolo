import { Controller } from "@hotwired/stimulus"

// A soft glow where a step goes: the browser compares the easy preview with a preview made without that step and
// lights up the pixels that differ. Both pictures come from our own origin, so the canvas can read them.
const WIDTH = 480
const THRESHOLD = 36

export default class extends Controller {
  static targets = ["canvas"]
  static values = { with: String, without: String }

  async connect() {
    if (!this.withValue || !this.withoutValue) return
    try {
      const [withImage, withoutImage] = await Promise.all([this.load(this.withValue), this.load(this.withoutValue)])
      this.draw(withImage, withoutImage)
    } catch {
      // No glow: the card still shows the step.
    }
  }

  load(src) {
    const image = new Image()
    image.src = src
    return image.decode().then(() => image)
  }

  draw(withImage, withoutImage) {
    const height = Math.round(WIDTH * withImage.naturalHeight / withImage.naturalWidth)
    const a = this.pixels(withImage, height), b = this.pixels(withoutImage, height)
    const canvas = this.canvasTarget
    canvas.width = WIDTH
    canvas.height = height
    const context = canvas.getContext("2d")
    const glow = context.createImageData(WIDTH, height)
    for (let i = 0; i < a.length; i += 4) {
      const difference = Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2])
      glow.data[i] = 255
      glow.data[i + 1] = 211
      glow.data[i + 2] = 105
      glow.data[i + 3] = Math.max(0, Math.min(220, (difference - THRESHOLD) * 4))
    }
    context.putImageData(glow, 0, 0)
    canvas.hidden = false
  }

  pixels(image, height) {
    const canvas = document.createElement("canvas")
    canvas.width = WIDTH
    canvas.height = height
    const context = canvas.getContext("2d", { willReadFrequently: true })
    context.drawImage(image, 0, 0, WIDTH, height)
    return context.getImageData(0, 0, WIDTH, height).data
  }
}
