// Blendolo's service worker: an offline shell only. Pages and photos are never cached here, so a kit stays private
// to the server. When a page can't load because the phone is offline, it shows the offline page instead.
const CACHE = "blendolo-shell-v1"
const OFFLINE_URL = "/offline.html"

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.add(new Request(OFFLINE_URL, { cache: "reload" }))))
  self.skipWaiting()
})

// Navigation preload: the browser asks for the page while this worker starts, instead of after, so a page opened
// from a link or the home screen doesn't wait for the worker first.
self.addEventListener("activate", (event) => {
  event.waitUntil(Promise.all([
    self.registration.navigationPreload?.enable(),
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
  ]))
  self.clients.claim()
})

self.addEventListener("fetch", (event) => {
  if (event.request.mode !== "navigate") return

  event.respondWith((async () => {
    try {
      return (await event.preloadResponse) || (await fetch(event.request))
    } catch {
      return caches.match(OFFLINE_URL)
    }
  })())
})
