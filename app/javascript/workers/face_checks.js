// The capture page's face checks, off the page's main thread: capture/checks.js starts this as a module worker. It
// runs MediaPipe's Face Landmarker and answers with only what the gates need (capture/gate.js summarize). It isn't in
// the import map (workers can't use one), so the page sends the URLs it needs. Messages, answered one at a time:
//
//   { type: "load", packageUrl, modelUrl, gateUrl }      -> { type: "ready" }, or { type: "unavailable", error }
//   { type: "video", id, frame: ImageBitmap, timestamp } -> { type: "video", id, summary, ms }
//   { type: "still", id, image: ImageBitmap }            -> { type: "still", id, faces: [[{ x, y }]] }
//   a request that fails                                 -> { type: "failed", id, error }

let gate, landmarker
let lastTimestamp = 0
let queue = Promise.resolve()

self.onmessage = ({ data }) => {
  queue = queue.then(() => answer(data))
}

async function answer(message) {
  try {
    if (message.type === "load") await load(message)
    else if (message.type === "video") video(message)
    else if (message.type === "still") await still(message)
  } catch (error) {
    const type = message.type === "load" ? "unavailable" : "failed"
    self.postMessage({ type, id: message.id, error: String(error?.message || error) })
  } finally {
    message.frame?.close()
    message.image?.close()
  }
}

async function load({ packageUrl, modelUrl, gateUrl }) {
  gate = await import(gateUrl)
  landmarker = await gate.loadLandmarker(packageUrl, modelUrl, { module: true })
  lastTimestamp = gate.warm(landmarker)
  self.postMessage({ type: "ready" })
}

function video({ id, frame, timestamp }) {
  const started = performance.now()
  // In video mode each frame's timestamp must be later than the last one's.
  lastTimestamp = Math.max(timestamp, lastTimestamp + 1)
  const result = landmarker.detectForVideo(frame, lastTimestamp)
  self.postMessage({ type: "video", id, summary: gate.summarize(result), ms: performance.now() - started })
}

async function still({ id, image }) {
  await landmarker.setOptions({ runningMode: "IMAGE" })
  try {
    const faces = (landmarker.detect(image).faceLandmarks || []).map((face) => face.map(({ x, y }) => ({ x, y })))
    self.postMessage({ type: "still", id, faces })
  } finally {
    await landmarker.setOptions({ runningMode: "VIDEO" })
  }
}
