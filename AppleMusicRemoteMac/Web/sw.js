// Apple Music Remote (AMR) - Service Worker for PWA
const CACHE_NAME = 'amr-shell-v6';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/style.css',
  '/app.js',
  '/manifest.json',
  '/apple-touch-icon.svg',
  '/apple-touch-icon.png',
  '/apple-touch-icon-180.png',
  '/apple-touch-icon-192.png',
  '/apple-touch-icon-512.png',
  '/assets/silence.m4a',
  '/assets/silence.wav',
  '/assets/stations/CoverPersonal.png',
  '/assets/stations/CoverDiscovery.png',
  '/assets/stations/CoverAppleMusic1.png',
  '/assets/stations/CoverHeavyRotation.svg',
  '/assets/stations/CoverElectronic.png',
  '/assets/stations/CoverRock.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch((err) => {
        console.warn('AMR ServiceWorker pre-cache notice:', err);
      });
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Always bypass cache for API endpoints, WebSocket, and dynamic search
  if (
    url.pathname.startsWith('/api/') ||
    url.pathname.startsWith('/ws') ||
    event.request.method !== 'GET'
  ) {
    return;
  }

  // Network-first for code assets (HTML, app.js, style.css) so updates are immediate
  if (
    event.request.headers.get('accept')?.includes('text/html') ||
    url.pathname === '/app.js' ||
    url.pathname === '/style.css' ||
    url.pathname === '/manifest.json'
  ) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Cache-first with background revalidation for static assets
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) {
        fetch(event.request)
          .then((networkRes) => {
            if (networkRes && networkRes.status === 200) {
              caches.open(CACHE_NAME).then((cache) => cache.put(event.request, networkRes));
            }
          })
          .catch(() => {});
        return cached;
      }
      return fetch(event.request).then((networkRes) => {
        if (networkRes && networkRes.status === 200) {
          const copy = networkRes.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        }
        return networkRes;
      });
    })
  );
});
