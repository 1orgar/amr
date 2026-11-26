// Apple Music Remote (AMR) - Service Worker for PWA
const CACHE_NAME = 'amr-shell-e87f1c26';

const SHELL_PATHS = new Set([
  '/',
  '/index.html',
  '/app.js',
  '/style.css',
  '/manifest.json',
  '/apple-touch-icon.svg'
]);

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

function normalizedCacheKey(url) {
  return new URL(url.pathname, url.origin).href;
}

function fetchShellWithTimeout(request, timeoutMs = 3500) {
  const controller = new AbortController();
  const timerId = setTimeout(() => controller.abort(), timeoutMs);
  return fetch(request, {
    cache: 'no-cache',
    signal: controller.signal
  }).finally(() => {
    clearTimeout(timerId);
  });
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) =>
        Promise.allSettled(
          STATIC_ASSETS.map((assetPath) => {
            const assetUrl = new URL(assetPath, self.location.origin);
            return fetch(assetUrl.href, { cache: 'no-cache' }).then((res) => {
              if (res && res.status === 200) {
                return cache.put(normalizedCacheKey(assetUrl), res);
              }
            });
          })
        ).catch((err) => {
          console.warn('AMR ServiceWorker pre-cache notice:', err);
        })
      )
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) =>
        Promise.all(
          keys.map((key) => {
            if (key !== CACHE_NAME && key.startsWith('amr-shell-')) {
              return caches.delete(key);
            }
            return undefined;
          })
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  if (url.origin !== self.location.origin) return;
  if (event.request.headers.has('range')) return;
  if (event.request.method !== 'GET') return;

  // Always bypass cache for API endpoints, WebSocket, audio streams, and live artwork
  if (
    url.pathname.startsWith('/api/') ||
    url.pathname.startsWith('/ws') ||
    url.pathname.startsWith('/stream/') ||
    url.pathname === '/artwork.jpg' ||
    url.pathname === '/sw.js'
  ) {
    return;
  }

  const acceptHeader = event.request.headers.get('accept') || '';
  const isHtmlNavigation = event.request.mode === 'navigate' || acceptHeader.includes('text/html');
  const isShellAsset = SHELL_PATHS.has(url.pathname) || isHtmlNavigation;

  // Network-first with 3.5s timeout and normalized cache keys for shell assets
  if (isShellAsset) {
    const targetPathname = SHELL_PATHS.has(url.pathname) ? url.pathname : '/';
    const cacheKey = new URL(targetPathname, url.origin).href;

    event.respondWith(
      fetchShellWithTimeout(event.request, 3500)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            event.waitUntil(
              caches.open(CACHE_NAME).then((cache) => cache.put(cacheKey, copy))
            );
          }
          return response;
        })
        .catch(() =>
          caches.open(CACHE_NAME).then((cache) =>
            cache.match(cacheKey).then((cached) => {
              if (cached) return cached;
              if (isHtmlNavigation) {
                return cache.match(new URL('/', url.origin).href)
                  .then((rootCached) => rootCached || cache.match(new URL('/index.html', url.origin).href));
              }
              return null;
            })
          ).then((cached) => cached || new Response('Offline', { status: 503, statusText: 'Offline' }))
        )
    );
    return;
  }

  // Cache-first with background revalidation for static assets (icons, silence.wav, station covers)
  const assetCacheKey = normalizedCacheKey(url);
  event.respondWith(
    caches.open(CACHE_NAME).then((cache) =>
      cache.match(assetCacheKey).then((cached) => {
        if (cached) {
          event.waitUntil(
            fetch(event.request)
              .then((networkRes) => {
                if (networkRes && networkRes.status === 200) {
                  return cache.put(assetCacheKey, networkRes.clone());
                }
              })
              .catch(() => {})
          );
          return cached;
        }
        return fetch(event.request)
          .then((networkRes) => {
            if (networkRes && networkRes.status === 200) {
              const copy = networkRes.clone();
              event.waitUntil(cache.put(assetCacheKey, copy));
            }
            return networkRes;
          })
          .catch(() => new Response('Offline', { status: 503, statusText: 'Offline' }));
      })
    )
  );
});
