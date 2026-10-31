// Colours and pictures from a face photo, in the browser: the median colour of the lips, upper lids, cheeks and
// forehead skin (in Lab, so it matches what eyes see), the sharpest of a burst, and the JPEG we upload.

// Face Landmarker mesh points (468 + irises). Each region is a list of [from, to, t]: a point t of the way from one
// landmark to the other, so samples sit on the lip body, the lid below the brow, the cheek apple and the forehead.
export const REGIONS = {
  lips: [
    [0, 13, 0.5], [37, 82, 0.5], [267, 312, 0.5], [40, 80, 0.5], [270, 310, 0.5],
    [17, 14, 0.5], [84, 87, 0.5], [314, 317, 0.5], [91, 88, 0.5], [321, 318, 0.5]
  ],
  lids: [[159, 52, 0.35], [158, 53, 0.35], [160, 65, 0.35], [386, 282, 0.35], [385, 283, 0.35], [387, 295, 0.35]],
  cheeks: [[205, 205, 0], [50, 50, 0], [425, 425, 0], [280, 280, 0]],
  skin: [[151, 151, 0], [108, 108, 0], [337, 337, 0], [9, 151, 0.5]]
}

// Samples are disks this share of the face's width across.
const RADIUS_OF_FACE = 0.025

// imageData: ImageData of the photo; landmarks: [{x, y}] normalised 0..1 to the photo.
// -> { lips: "#RRGGBB", lids: ..., cheeks: ..., skin: ... } for the regions asked for.
export function sampleRegions(imageData, landmarks, regions = Object.keys(REGIONS)) {
  const { width, height } = imageData
  const xs = landmarks.map((point) => point.x)
  const radius = Math.max(2, Math.round((Math.max(...xs) - Math.min(...xs)) * width * RADIUS_OF_FACE))
  const result = {}

  for (const region of regions) {
    const labs = []
    for (const [from, to, t] of REGIONS[region]) {
      const a = landmarks[from], b = landmarks[to]
      if (!a || !b) continue
      const cx = Math.round((a.x + (b.x - a.x) * t) * width)
      const cy = Math.round((a.y + (b.y - a.y) * t) * height)
      for (let dy = -radius; dy <= radius; dy++) {
        for (let dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy > radius * radius) continue
          const x = cx + dx, y = cy + dy
          if (x < 0 || y < 0 || x >= width || y >= height) continue
          const i = (y * width + x) * 4
          labs.push(rgbToLab(imageData.data[i], imageData.data[i + 1], imageData.data[i + 2]))
        }
      }
    }
    if (labs.length) result[region] = labToHex(medianLab(labs))
  }
  return result
}

function medianLab(labs) {
  return [0, 1, 2].map((channel) => median(labs.map((lab) => lab[channel])))
}

function median(values) {
  const sorted = values.slice().sort(byNumber)
  const middle = sorted.length >> 1
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

const byNumber = (a, b) => a - b

// sRGB (0..255) to CIE Lab (D65).
export function rgbToLab(r, g, b) {
  const [x, y, z] = rgbToXyz(r, g, b)
  const f = (t) => (t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116)
  const fx = f(x / 0.95047), fy = f(y / 1), fz = f(z / 1.08883)
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
}

export function labToHex([l, a, b]) {
  const fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
  const inverse = (t) => (t ** 3 > 216 / 24389 ? t ** 3 : (116 * t - 16) / (24389 / 27))
  const [x, y, z] = [inverse(fx) * 0.95047, inverse(fy), inverse(fz) * 1.08883]
  const linear = [
    3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
    -0.969266 * x + 1.8760108 * y + 0.041556 * z,
    0.0556434 * x - 0.2040259 * y + 1.0572252 * z
  ]
  return "#" + linear.map((c) => {
    const s = c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055
    return Math.round(Math.min(1, Math.max(0, s)) * 255).toString(16).padStart(2, "0")
  }).join("").toUpperCase()
}

function rgbToXyz(r, g, b) {
  const [lr, lg, lb] = [r, g, b].map((v) => {
    const c = v / 255
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  })
  return [
    0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb,
    0.2126729 * lr + 0.7151522 * lg + 0.072175 * lb,
    0.0193339 * lr + 0.119192 * lg + 0.9503041 * lb
  ]
}

// How sharp a frame is: the variance of its Laplacian, on a small grey copy. Tremor blur lowers it.
export function sharpness(source, width = 256) {
  const height = Math.max(1, Math.round(width * (source.videoHeight || source.height) / (source.videoWidth || source.width)))
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext("2d", { willReadFrequently: true })
  context.drawImage(source, 0, 0, width, height)
  const { data } = context.getImageData(0, 0, width, height)
  const grey = new Float32Array(width * height)
  for (let i = 0; i < grey.length; i++) grey[i] = 0.299 * data[i * 4] + 0.587 * data[i * 4 + 1] + 0.114 * data[i * 4 + 2]

  let sum = 0, sumOfSquares = 0, count = 0
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const i = y * width + x
      const value = grey[i - width] + grey[i + width] + grey[i - 1] + grey[i + 1] - 4 * grey[i]
      sum += value
      sumOfSquares += value * value
      count++
    }
  }
  const mean = sum / count
  return sumOfSquares / count - mean * mean
}

// The size we upload: width a multiple of 8, height under 1080 (the provider's limits), never larger than the source.
export function uploadSize(width, height) {
  const scale = Math.min(1, 1072 / height)
  return { width: Math.max(8, Math.floor(width * scale / 8) * 8), height: Math.max(8, Math.round(height * scale)) }
}

// Draws the source at the upload size and encodes it as a JPEG Blob.
export function toJpeg(source) {
  const { width, height } = uploadSize(source.videoWidth || source.naturalWidth || source.width,
    source.videoHeight || source.naturalHeight || source.height)
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  canvas.getContext("2d").drawImage(source, 0, 0, width, height)
  return new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92))
}

// The pixels of a source (image, video or canvas) at its own size.
export function pixels(source) {
  const width = source.videoWidth || source.naturalWidth || source.width
  const height = source.videoHeight || source.naturalHeight || source.height
  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext("2d", { willReadFrequently: true })
  context.drawImage(source, 0, 0, width, height)
  return context.getImageData(0, 0, width, height)
}
