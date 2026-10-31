import { loadLandmarker, summarize, warm } from "capture/gate"

// The face checks' landmarker, kept off the page's main thread where the browser allows it, so the page stays quick
// to answer taps while the camera shows. A module worker (workers/face_checks.js) runs MediaPipe on small copies of
// camera frames and sends back summaries (capture/gate.js summarize). Where module workers, OffscreenCanvas or
// ImageBitmap are missing (older Safari), or the worker can't start, the page runs it itself: the same small frames,
// checked less often.
//
// startChecks({ packageUrl, modelUrl, workerUrl, gateUrl }) -> checks, once the landmarker is ready:
//   kind          "worker" or "page"
//   video(video, timestamp)  the summary of the camera's current frame; null while another frame is being checked
//   still(source)            the face landmarks ([{x, y}] per face) of a photo, image or canvas
//   close()                  stops the worker or frees the landmarker

// The width of the frames checked: plenty for a face a quarter of the frame wide, and quick to look at.
const FRAME_WIDTH = 384

export async function startChecks({ packageUrl, modelUrl, workerUrl, gateUrl }) {
  if (workerUrl && gateUrl && typeof Worker === "function" && typeof OffscreenCanvas === "function" &&
      typeof createImageBitmap === "function") {
    try {
      return await WorkerChecks.start({ packageUrl, modelUrl, gateUrl }, workerUrl)
    } catch {
      // The page runs the checks itself.
    }
  }
  return PageChecks.start(packageUrl, modelUrl)
}

class WorkerChecks {
  kind = "worker"

  // The worker starts from a blob: URL that imports workers/face_checks.js. A worker started from our assets' URL
  // would get no content security policy (assets are sent without one); one started from a blob: URL keeps the
  // page's, so it may fetch only what the page may: MediaPipe's package and model, not its usage logs.
  static start(urls, workerUrl) {
    const script = `import ${JSON.stringify(new URL(workerUrl, location.href).href)}`
    const blobUrl = URL.createObjectURL(new Blob([script], { type: "text/javascript" }))
    const checks = new WorkerChecks(new Worker(blobUrl, { type: "module" }))
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
    worker.onmessage = ({ data }) => this.receive(data)
    worker.onerror = (event) => this.stopped(new Error(event.message || "The face checks stopped"))
  }

  async video(video, timestamp) {
    if (this.busy || this.broken) return null
    this.busy = true
    try {
      const frame = await smallBitmap(video)
      return (await this.request({ type: "video", frame, timestamp }, [frame])).summary
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
      this.requests.set(id, { resolve, reject })
      this.worker.postMessage({ ...message, id }, transfer)
    })
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

class PageChecks {
  kind = "page"

  static async start(packageUrl, modelUrl) {
    return new PageChecks(await loadLandmarker(packageUrl, modelUrl))
  }

  constructor(landmarker) {
    this.landmarker = landmarker
    this.lastTimestamp = warm(landmarker)
  }

  async video(video, timestamp) {
    if (this.busy) return null
    this.busy = true
    let frame
    try {
      frame = await smallFrame(video)
      // In video mode each frame's timestamp must be later than the last one's.
      this.lastTimestamp = Math.max(timestamp, this.lastTimestamp + 1)
      return summarize(this.landmarker.detectForVideo(frame, this.lastTimestamp))
    } finally {
      frame?.close?.()
      this.busy = false
    }
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

// A small copy of the camera's current frame: an ImageBitmap where the browser can make one, otherwise a canvas.
async function smallFrame(video) {
  const { resizeWidth: width, resizeHeight: height } = smallSize(video)
  if (typeof createImageBitmap === "function") {
    try {
      return await createImageBitmap(video, { resizeWidth: width, resizeHeight: height, resizeQuality: "low" })
    } catch {
      // Drawn on a canvas below.
    }
  }
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  canvas.getContext("2d").drawImage(video, 0, 0, width, height)
  return canvas
}
