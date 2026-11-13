//
//  WebUIContent.swift
//  AppleMusicRemoteMac
//
//  Embedded Web UI content for Apple Music Remote.
//  HTML, CSS, and JS are split into respective WebUIContent+*.swift extensions.
//

import Foundation

public enum WebUIContent {
    public static let manifestJSON: String = #"""
{
  "name": "Apple Music Remote",
  "short_name": "AMR",
  "description": "Bit-Perfect High-Fidelity Remote for Apple Music on macOS",
  "id": "/",
  "start_url": "/?pwa=1",
  "scope": "/",
  "display": "standalone",
  "display_override": [
    "standalone",
    "fullscreen",
    "window-controls-overlay"
  ],
  "orientation": "any",
  "background_color": "#000000",
  "theme_color": "#000000",
  "categories": [
    "music",
    "entertainment",
    "utilities"
  ],
  "icons": [
    {
      "src": "/apple-touch-icon.svg",
      "sizes": "any",
      "type": "image/svg+xml",
      "purpose": "any"
    },
    {
      "src": "/apple-touch-icon-180.png",
      "sizes": "180x180",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/apple-touch-icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/apple-touch-icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "/apple-touch-icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/apple-touch-icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "/apple-touch-icon.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any"
    }
  ]
}
"""#

    public static let swJS: String = #"""
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
"""#

    public static let appleTouchIconSVG: String = #"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#141416"/>
      <stop offset="100%" stop-color="#000000"/>
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.08"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>
  
  <!-- Background with subtle border -->
  <rect width="512" height="512" rx="112" fill="url(#bgGrad)"/>
  <rect width="512" height="512" rx="112" fill="url(#glow)"/>
  <rect x="2" y="2" width="508" height="508" rx="110" fill="none" stroke="#262628" stroke-width="4"/>

  <!-- High-fidelity minimalist soundwave / audio core -->
  <g fill="#ffffff">
    <!-- Bar 1 -->
    <rect x="96" y="216" width="20" height="80" rx="10"/>
    <!-- Bar 2 -->
    <rect x="136" y="176" width="20" height="160" rx="10"/>
    <!-- Bar 3 -->
    <rect x="176" y="128" width="20" height="256" rx="10"/>
    <!-- Bar 4 -->
    <rect x="216" y="200" width="20" height="112" rx="10"/>
    <!-- Bar 5 -->
    <rect x="256" y="96" width="20" height="320" rx="10"/>
    <!-- Bar 6 -->
    <rect x="296" y="160" width="20" height="192" rx="10"/>
    <!-- Bar 7 -->
    <rect x="336" y="120" width="20" height="272" rx="10"/>
    <!-- Bar 8 -->
    <rect x="376" y="192" width="20" height="128" rx="10"/>
    <!-- Bar 9 -->
    <rect x="416" y="232" width="20" height="48" rx="10"/>
  </g>

  <!-- Bit-perfect badge text indicator at bottom center -->
  <text x="256" y="455" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif" font-size="22" font-weight="700" letter-spacing="5" fill="#8e8e93">BIT-PERFECT</text>
</svg>
"""#
}
