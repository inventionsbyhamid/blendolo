// The capture gates: is this frame a good photo for a makeup preview? Works on a summary of a Face Landmarker result
// (summarize), so it can be checked with recorded results as well as the live camera, and the worker that runs the
// landmarker (workers/face_checks.js) only has to send back a few numbers per frame.
//
// One face, 25 to 60% of the frame wide, looking straight on (yaw and pitch within 10 degrees), eyes open (blink under
// 0.4; squint under 0.75, as smiling and older eyes read as squinting), mouth relaxed (jawOpen under 0.3), then still
// for a second.

export const MESSAGES = {
  manyFaces: "Try a photo of just you",
  closer: "Come a little closer",
  back: "Step back a little",
  straight: "Look straight at the phone",
  eyes: "Open your eyes wide",
  still: "Hold still",
  done: "Got it"
}

// maxMove: a share of the frame per 100 ms (movement).
export const LIMITS = { minWidth: 0.25, maxWidth: 0.6, maxAngle: 10, maxBlink: 0.4, maxSquint: 0.75, maxJaw: 0.3,
  stillFor: 1000, maxMove: 0.012 }

const EYES = ["eyeBlinkLeft", "eyeBlinkRight", "eyeSquintLeft", "eyeSquintRight"]

// Points that show the head moving: nose tip, eye corners, chin.
const STILL_POINTS = [1, 33, 263, 152]

// result: { faceLandmarks: [[{x, y}]], faceBlendshapes: [{ categories: [{ categoryName, score }] }],
//           facialTransformationMatrixes: [{ data: [16 numbers, column-major] }] }
// -> { faces: how many, width: the first face's, angles: { yaw, pitch } or null,
//      scores: { eyeBlinkLeft, ..., jawOpen }, points: the first face's STILL_POINTS as [{x, y}] or null }
export function summarize(result) {
  const faces = result?.faceLandmarks || []
  const face = faces[0]
  const matrix = result?.facialTransformationMatrixes?.[0]?.data
  const scores = blendshapes(result)
  return {
    faces: faces.length,
    width: face ? faceWidth(face) : 0,
    angles: matrix ? headAngles(matrix) : null,
    scores: Object.fromEntries([...EYES, "jawOpen"].map((name) => [name, scores[name] || 0])),
    points: face ? STILL_POINTS.map((index) => ({ x: face[index].x, y: face[index].y })) : null
  }
}

// summary (from summarize) -> { ok: true } or { ok: false, message }
export function evaluate(summary) {
  if (summary.faces > 1) return fail(MESSAGES.manyFaces)
  if (summary.faces === 0) return fail(MESSAGES.straight)

  if (summary.width < LIMITS.minWidth) return fail(MESSAGES.closer)
  if (summary.width > LIMITS.maxWidth) return fail(MESSAGES.back)

  const { angles } = summary
  const turned = angles && (Math.abs(angles.yaw) > LIMITS.maxAngle || Math.abs(angles.pitch) > LIMITS.maxAngle)
  if (turned) return fail(MESSAGES.straight)

  const { scores } = summary
  const eyesOpen = Math.max(scores.eyeBlinkLeft, scores.eyeBlinkRight) < LIMITS.maxBlink &&
    Math.max(scores.eyeSquintLeft, scores.eyeSquintRight) < LIMITS.maxSquint
  if (!eyesOpen) return fail(MESSAGES.eyes)
  if (scores.jawOpen >= LIMITS.maxJaw) return fail(MESSAGES.still)

  return { ok: true }
}

// How much of the frame's width the face takes, 0..1.
export function faceWidth(landmarks) {
  const xs = landmarks.map((point) => point.x)
  return Math.max(...xs) - Math.min(...xs)
}

// Head turn (yaw) and nod (pitch) in degrees from the face's 4x4 transformation matrix (column-major).
export function headAngles(m) {
  const yaw = Math.asin(Math.max(-1, Math.min(1, -m[2]))) * 180 / Math.PI
  const pitch = Math.atan2(m[6], m[10]) * 180 / Math.PI
  return { yaw, pitch }
}

export function blendshapes(result) {
  const categories = result?.faceBlendshapes?.[0]?.categories || []
  return Object.fromEntries(categories.map((category) => [category.categoryName, category.score]))
}

// How far the face moved between two checks (their summaries' points, elapsed ms apart), as a share of the frame per
// 100 ms. Checks run every 200 ms or so, less often on a slow phone; per 100 ms, a slow drift counts the same however
// often they run.
export function movement(previous, current, elapsed = 100) {
  if (!previous || !current) return Infinity
  const distances = previous.map((point, index) => Math.hypot(point.x - current[index].x, point.y - current[index].y))
  const average = distances.reduce((sum, distance) => sum + distance, 0) / distances.length
  return average * 100 / Math.max(100, elapsed)
}

function fail(message) {
  return { ok: false, message }
}

// Loads MediaPipe's Face Landmarker from the pinned package and model (the content security policy allows only these).
// module: load MediaPipe's WebAssembly glue as an ES module, as a module worker needs (it can't use importScripts).
export async function loadLandmarker(packageUrl, modelUrl, { module = false } = {}) {
  const vision = await import(`${packageUrl}vision_bundle.mjs`)
  const fileset = await vision.FilesetResolver.forVisionTasks(`${packageUrl}wasm`, module)
  const options = (delegate) => ({
    baseOptions: { modelAssetPath: modelUrl, delegate },
    runningMode: "VIDEO",
    numFaces: 2,
    outputFaceBlendshapes: true,
    outputFacialTransformationMatrixes: true
  })
  try {
    return await vision.FaceLandmarker.createFromOptions(fileset, options("GPU"))
  } catch {
    return await vision.FaceLandmarker.createFromOptions(fileset, options("CPU"))
  }
}

// Runs the landmarker once on a blank frame, so its slow first run (setting up the model) happens while it loads, not
// on the first frame of the camera it checks. Returns the timestamp it used (video mode needs later ones after it).
export function warm(landmarker) {
  try {
    landmarker.detectForVideo(new ImageData(64, 64), 1)
  } catch {
    // The first real frame sets it up instead.
  }
  return 1
}
