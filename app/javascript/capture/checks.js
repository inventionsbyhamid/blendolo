import { blankFrame, loadLandmarker, summarize, warm } from "capture/gate"

// The face checks' landmarker, kept off the page's main thread where the browser allows it, so the page stays quick
// to answer taps while the camera shows. A module worker (workers/face_checks.js) runs MediaPipe on small copies of
// camera frames and sends back summaries (capture/gate.js summarize). Where module workers, OffscreenCanvas or
// ImageBitmap are missing (older Safari), or the worker can't start, the page runs it itself: the same small frames,
// drawn on a canvas, checked less often. The page also takes over when a running worker fails (capture_controller.js).
//
// startChecks({ packageUrl, modelUrl, workerUrl, gateUrl }) -> checks, once the landmarker is ready:
//   kind          "worker" or "page"
//   broken        set once the worker has failed for good
//   video(video, timestamp)  the summary of the camera's current frame (blank: true when no face was found because
//                            the frame was empty); null while another frame is being checked; fails once broken
//   still(source)            the face landmarks ([{x, y}] per face) of a photo, image or canvas
//   close()                  stops the worker or frees the landmarker

// The width of the frames checked: plenty for a face a quarter of the frame wide, and quick to look at.
const FRAME_WIDTH = 384
// A worker that hasn't answered within this long, or 10 times its slowest frame check so far (a slow phone's still
// photo check takes several frame checks' time), hangs: it is stopped, and what it was asked fails. A photo being
// reviewed is then kept without sampled colours, rather than leaving the screen waiting.
const REPLY_WAIT_MS = 5000
const REPLY_WAIT_CHECKS = 10

export async function startChecks({ packageUrl, modelUrl, workerUrl, gateUrl }) {
  if (workerUrl && gateUrl && typeof Worker === "function" && typeof createImageBitmap === "function" &&
      offscreenWebgl2()) {
    try {
      return await WorkerChecks.start({ packageUrl, modelUrl, gateUrl }, workerUrl)
    } catch {
      // The page runs the checks itself.
    }
  }
  return PageChecks.start(packageUrl, modelUrl)
}

// Exported for its tests; pages use startChecks.
export class WorkerChecks {
  kind = "worker"

  // The worker starts from a blob: URL that imports workers/face_checks.js. A worker started from our assets' URL
  // would get no content security policy (assets are sent without one); one started from a blob: URL keeps the
  // page's, so it may fetch only what the page may: MediaPipe's package and model, not its usage logs.
  static start(urls, workerUrl) {
    const script = `import ${JSON.stringify(new URL(workerUrl, location.href).href)}`
    const blobUrl = URL.createObjectURL(new Blob([script], { type: "text/javascript" }))
    let worker
    try {
      worker = new Worker(blobUrl, { type: "module" })
    } catch (error) {
      URL.revokeObjectURL(blobUrl)
      throw error
    }
    const checks = new WorkerChecks(worker)
    checks.blobUrl = blobUrl
    return new Promise((resolve, reject) => {
      checks.loading = { resolve, reject }
      checks.worker.postMessage({ type: "load", ...urls })
    }).then(() => checks, (error) => {
      checks.close()
      throw error
    })
  }

  constructor(worker) {
    this.worker = worker
    this.requests = new Map()
    this.nextId = 1
    this.slowest = 0
    worker.onmessage = ({ data }) => this.receive(data)
    worker.onerror = (event) => this.stopped(new Error(event.message || "The face checks stopped"))
  }

  async video(video, timestamp) {
    if (this.broken) throw this.broken
    if (this.busy) return null
    this.busy = true
    try {
      const started = performance.now()
      const frame = await smallBitmap(video)
      const { summary } = await this.request({ type: "video", frame, timestamp }, [frame])
      this.slowest = Math.max(this.slowest, performance.now() - started)
      return summary
    } finally {
      this.busy = false
    }
  }

  async still(source) {
    const image = await createImageBitmap(source, { imageOrientation: "from-image" })
      .catch(() => createImageBitmap(source))
    return (await this.request({ type: "still", image }, [image])).faces
  }

  close() {
    this.stopped(new Error("The face checks were closed"))
    this.worker.terminate()
    URL.revokeObjectURL(this.blobUrl)
  }

  request(message, transfer) {
    if (this.broken) {
      transfer.forEach((bitmap) => bitmap.close())
      return Promise.reject(this.broken)
    }
    const id = this.nextId++
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.hung(), Math.max(REPLY_WAIT_MS, REPLY_WAIT_CHECKS * this.slowest))
      const settled = (then) => (value) => {
        clearTimeout(timer)
        then(value)
      }
      this.requests.set(id, { resolve: settled(resolve), reject: settled(reject) })
      try {
        this.worker.postMessage({ ...message, id }, transfer)
      } catch (error) {
        this.requests.get(id).reject(error)
        this.requests.delete(id)
        transfer.forEach((bitmap) => bitmap.close())
      }
    })
  }

  // No answer in time: the worker is stuck, say on a GPU call that never returns.
  hung() {
    this.stopped(new Error("The face checks stopped answering"))
    this.worker.terminate()
  }

  receive(message) {
    if (message.type === "ready" || message.type === "unavailable") {
      const loading = this.loading
      this.loading = null
      return message.type === "ready" ? loading?.resolve() : loading?.reject(new Error(message.error))
    }
    const request = this.requests.get(message.id)
    if (!request) return
    this.requests.delete(message.id)
    if (message.type === "failed") request.reject(new Error(message.error))
    else request.resolve(message)
  }

  // The worker can't answer any more (it failed, or was closed): whatever it was asked fails.
  stopped(error) {
    this.broken = error
    this.loading?.reject(error)
    this.loading = null
    this.requests.forEach(({ reject }) => reject(error))
    this.requests.clear()
  }
}

// MediaPipe in a worker draws on an OffscreenCanvas with WebGL2. Safari 16.4 to 16.7 have the canvas without WebGL2
// in it, where MediaPipe would load its WebAssembly twice in the worker before failing; they go straight to the page.
function offscreenWebgl2() {
  if (typeof OffscreenCanvas !== "function") return false
  try {
    const context = new OffscreenCanvas(1, 1).getContext("webgl2")
    context?.getExtension("WEBGL_lose_context")?.loseContext()
    return !!context
  } catch {
    return false
  }
}

class PageChecks {
  kind = "page"

  static async start(packageUrl, modelUrl) {
    return new PageChecks(await loadLandmarker(packageUrl, modelUrl))
  }

  constructor(landmarker) {
    this.landmarker = landmarker
    this.lastTimestamp = warm(landmarker)
    this.canvas = document.createElement("canvas")
  }

  // Draws the frame small on a canvas rather than making a bitmap: drawing a video is the most dependable way to get
  // its picture, and the page is where the checks end up when the worker's bitmaps came out empty.
  async video(video, timestamp) {
    const { resizeWidth: width, resizeHeight: height } = smallSize(video)
    this.canvas.width = width
    this.canvas.height = height
    this.canvas.getContext("2d").drawImage(video, 0, 0, width, height)
    // In video mode each frame's timestamp must be later than the last one's.
    this.lastTimestamp = Math.max(timestamp, this.lastTimestamp + 1)
    const summary = summarize(this.landmarker.detectForVideo(this.canvas, this.lastTimestamp))
    if (summary.faces === 0) summary.blank = blankFrame(this.canvas)
    return summary
  }

  async still(source) {
    await this.landmarker.setOptions({ runningMode: "IMAGE" })
    try {
      return this.landmarker.detect(source).faceLandmarks || []
    } finally {
      await this.landmarker.setOptions({ runningMode: "VIDEO" }).catch(() => {})
    }
  }

  close() {
    this.landmarker.close()
  }
}

// The video's frame size scaled down to FRAME_WIDTH wide (never up).
function smallSize(video) {
  const resizeWidth = Math.min(FRAME_WIDTH, video.videoWidth)
  return { resizeWidth, resizeHeight: Math.max(1, Math.round(video.videoHeight * resizeWidth / video.videoWidth)) }
}

// A small copy of the camera's current frame as an ImageBitmap, to send to the worker. A browser that can't scale a
// bitmap as it makes one gets it drawn small first.
async function smallBitmap(video) {
  const size = smallSize(video)
  try {
    return await createImageBitmap(video, { ...size, resizeQuality: "low" })
  } catch {
    const canvas = new OffscreenCanvas(size.resizeWidth, size.resizeHeight)
    canvas.getContext("2d").drawImage(video, 0, 0, size.resizeWidth, size.resizeHeight)
    return canvas.transferToImageBitmap()
  }
}
