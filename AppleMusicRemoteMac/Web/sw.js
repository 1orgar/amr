// Apple Music Remote (AMR) - Service Worker for PWA
const CACHE_NAME = 'amr-shell-v18';
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
  '/assets/stations/CoverPersonal.png',
  '/assets/stations/CoverDiscovery.png',
  '/assets/stations/CoverAppleMusic1.png',
  '/assets/stations/CoverHits.png',
  '/assets/stations/CoverCountry.png',
  '/assets/stations/CoverHeavyRotation.svg',
  '/assets/stations/CoverChill.png',
  '/assets/stations/CoverPop.png',
  '/assets/stations/CoverElectronic.png',
  '/assets/stations/CoverDeepHouse.png',
  '/assets/stations/CoverRock.png',
  '/assets/stations/CoverHipHop.png',
  '/assets/stations/CoverJazz.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return Promise.allSettled(STATIC_ASSETS.map((u) => cache.add(u))).catch((err) => {
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
          if (key !== CACHE_NAME && key.startsWith('amr-shell-')) {
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

  if (url.origin !== self.location.origin) return;
  if (event.request.headers.has('range')) return;

  // Always bypass cache for API endpoints, WebSocket, audio streams, live artwork, and non-GET requests
  if (
    url.pathname.startsWith('/api/') ||
    url.pathname.startsWith('/ws') ||
    url.pathname.startsWith('/stream/') ||
    url.pathname === '/artwork.jpg' ||
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
        .catch(() =>
          caches.match(event.request)
            .then((cached) => cached || caches.match(event.request, { ignoreSearch: true }))
            .then((cached) => cached || new Response('Offline', { status: 503, statusText: 'Offline' }))
        )
    );
    return;
  }

  // Cache-first with background revalidation for static assets
  event.respondWith(
    caches.match(event.request)
      .then((exact) => exact || caches.match(event.request, { ignoreSearch: true }))
      .then((cached) => {
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
        return fetch(event.request)
          .then((networkRes) => {
            if (networkRes && networkRes.status === 200) {
              const copy = networkRes.clone();
              caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
            }
            return networkRes;
          })
          .catch(() => new Response('Offline', { status: 503, statusText: 'Offline' }));
      })
  );
});
