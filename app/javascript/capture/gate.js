// The capture gates: is this frame a good photo for a makeup preview? Works on a summary of a Face Landmarker result
// (summarize), so it can be checked with recorded results as well as the live camera, and only a few numbers per
// frame have to be kept.
//
// One face, 25 to 60% of the frame wide, looking straight on (yaw and pitch within 10 degrees), eyes open (blink and
// squint under 0.4), mouth relaxed (jawOpen under 0.3), then still for a second.

export const MESSAGES = {
  manyFaces: "Try a photo of just you",
  closer: "Come a little closer",
  back: "Step back a little",
  straight: "Look straight at the phone",
  eyes: "Open your eyes wide",
  still: "Hold still",
  done: "Got it"
}

export const LIMITS = { minWidth: 0.25, maxWidth: 0.6, maxAngle: 10, maxEyes: 0.4, maxJaw: 0.3, stillFor: 1000, maxMove: 0.012 }

const EYES = ["eyeBlinkLeft", "eyeBlinkRight", "eyeSquintLeft", "eyeSquintRight"]

// Points that show the head moving: nose tip, eye corners, chin.
const STILL_POINTS = [1, 33, 263, 152]

// result: { faceLandmarks: [[{x, y}]], faceBlendshapes: [{ categories: [{ categoryName, score }] }],
//           facialTransformationMatrixes: [{ data: [16 numbers, column-major] }] }
// -> { faces: how many, width: of the first face, angles: { yaw, pitch } or null, scores: { eyeBlinkLeft, ..., jawOpen },
//      points: the first face's STILL_POINTS as [{x, y}] or null }
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
  if (angles && (Math.abs(angles.yaw) > LIMITS.maxAngle || Math.abs(angles.pitch) > LIMITS.maxAngle)) return fail(MESSAGES.straight)

  if (Math.max(...EYES.map((name) => summary.scores[name])) >= LIMITS.maxEyes) return fail(MESSAGES.eyes)
  if (summary.scores.jawOpen >= LIMITS.maxJaw) return fail(MESSAGES.still)

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

// How far the face moved between two frames (their summaries' points), as a share of the frame.
export function movement(previous, current) {
  if (!previous || !current) return Infinity
  const distances = previous.map((point, index) => Math.hypot(point.x - current[index].x, point.y - current[index].y))
  return distances.reduce((sum, distance) => sum + distance, 0) / distances.length
}

function fail(message) {
  return { ok: false, message }
}

// Loads MediaPipe's Face Landmarker from the pinned package and model (the content security policy allows only these).
export async function loadLandmarker(packageUrl, modelUrl) {
  const vision = await import(`${packageUrl}vision_bundle.mjs`)
  const fileset = await vision.FilesetResolver.forVisionTasks(`${packageUrl}wasm`)
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
