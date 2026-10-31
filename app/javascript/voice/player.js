// Blendolo's voice. Step cards and the hands-free photo's spoken help are read in one recorded voice: each line was
// recorded ahead of time (script/voice/generate.rb) and is served from /voice/<key>.mp3, where key is the SHA-256 of
// the line's text with its spaces tidied (Voice.key in Ruby). A page hands over which of its lines have a recording,
// as { key: version }. A line plays on one audio element shared by the whole visit; a line without a recording, or
// one that won't play, is read by the phone's own voice (Web Speech) a little slower than usual, as before.
//
// One line at a time: speaking a line stops the one before. onend runs when a line has been read to the end (or
// couldn't be read at all: "unavailable"), never for a line that was stopped.

const RATE = 0.9
// How long a recording may take to start before the phone's own voice reads the line instead.
const START_WITHIN_MS = 3000

let element = null
let current = null // the line being read: { text, onend, audio, speech }
const keys = new Map() // text -> key, or null where the browser can't hash (crypto.subtle needs HTTPS)

export function normalize(text) {
  return String(text ?? "").replace(/\s+/g, " ").trim()
}

// A card's paragraphs as one text: each ends with a full stop (or its own ! or ?), one space between (Voice.join).
export function joinParts(parts) {
  return parts.map(normalize).filter(Boolean).map((part) => /[.!?]$/.test(part) ? part : `${part}.`).join(" ")
}

// The line's key: a promise, settled at once for a text hashed before.
export async function key(text) {
  text = normalize(text)
  if (keys.has(text)) return keys.get(text)
  let hex = null
  try {
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
    hex = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("")
  } catch {
    // No crypto.subtle (a page not on HTTPS): every line is read by the phone's own voice.
  }
  keys.set(text, hex)
  return hex
}

export function speaking() {
  return current !== null
}

// Reads text aloud: its recording when voices has its key, else the phone's own voice. A text hashed before (key)
// starts playing at once, inside the tap that asked for it, which iOS needs before it plays any sound.
export function speak(text, { voices = {}, onend = () => {} } = {}) {
  stop()
  const line = { text: normalize(text), onend }
  current = line
  if (keys.has(line.text)) start(line, keys.get(line.text), voices)
  else key(line.text).then((hex) => { if (current === line) start(line, hex, voices) })
  return line
}

// Stops the line being read (or only this line, when it's the one being read).
export function stop(line = current) {
  if (!line || line !== current) return
  current = null
  if (line.audio) element.pause()
  if (line.speech) window.speechSynthesis?.cancel()
}

function start(line, hex, voices) {
  const version = hex && voices[hex]
  if (!version) return speakAloud(line)

  const audio = player()
  line.audio = true
  audio.src = `/voice/${hex}.mp3?v=${encodeURIComponent(version)}`
  const late = setTimeout(() => giveUp(line), START_WITHIN_MS)
  Promise.resolve(audio.play()).then(() => clearTimeout(late), () => {
    clearTimeout(late)
    giveUp(line) // Blocked (no tap yet on iOS, say), or the file didn't load.
  })
}

// The recording can't be played: the phone's own voice reads the line instead.
function giveUp(line) {
  if (current !== line || !line.audio) return
  line.audio = false
  element.pause()
  speakAloud(line)
}

function speakAloud(line) {
  const speech = window.speechSynthesis
  // Nothing can read it. Said after speak() returns, as the other endings are.
  if (!speech || typeof SpeechSynthesisUtterance === "undefined") return queueMicrotask(() => finish(line, "unavailable"))

  line.speech = true
  const utterance = new SpeechSynthesisUtterance(line.text)
  utterance.rate = RATE
  utterance.onend = utterance.onerror = () => finish(line)
  speech.cancel()
  speech.speak(utterance)
}

function finish(line, reason = "ended") {
  if (current !== line) return
  current = null
  line.onend(reason)
}

function player() {
  if (element) return element
  element = new Audio()
  element.preload = "auto"
  element.addEventListener("ended", () => { if (current?.audio) finish(current) })
  element.addEventListener("error", () => { if (current?.audio) giveUp(current) })
  return element
}

// iOS plays sound from an audio element only once a tap has started it (or loaded it). The first tap anywhere in the
// visit loads the shared element, so spoken help that starts on its own later (the photo page's, after its camera
// starts) can play. Loading without a source plays nothing and doesn't stop the person's music.
function unlock() {
  if (current) return // Loading now would cut off the line being read: the next tap tries again.
  player().load()
  for (const type of UNLOCK_EVENTS) document.removeEventListener(type, unlock, true)
}

const UNLOCK_EVENTS = ["click", "touchend", "keydown"]
for (const type of UNLOCK_EVENTS) document.addEventListener(type, unlock, true)
