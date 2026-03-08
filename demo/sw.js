// ═══════════════════════════════════════════════════════════════════════════
// InterPlanet — Service Worker (Story 5.2)
// Strategy:
//   Cache-First  — app shell (HTML, JS, CSS, fonts, favicons)
//   Network-First — external APIs (weather, HDTN, SLM, geocoding)
// ═══════════════════════════════════════════════════════════════════════════

const CACHE_VERSION = 'interplanet-v1.14.0';

const SHELL_URLS = [
  '/',
  '/index.html',
  '/sky.js?v=1.14.0',
  '/planet-time.js?v=1.14.0',
  '/assets/sky.css?v=1.14.0',
  '/assets/i18n.js?v=1.14.0',
  '/assets/holidays-data.js?v=1.14.0',
  '/assets/un-days.js?v=1.14.0',
  '/ltx.html',
  '/dashboard.html',
  '/playground.html',
  '/events.html',
  '/manifest.json',
  '/assets/favicon.ico',
  '/assets/favicon-32x32.png',
  '/assets/favicon-16x16.png',
  '/assets/favicon-192x192.png',
  '/assets/favicon-512x512.png',
  '/assets/apple-touch-icon.png',
  // Font Awesome (CDN) — cache on first fetch
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/fontawesome.min.css',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/solid.min.css',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/brands.min.css',
];

// Domains that always go Network-First (external APIs, never cached long-term)
const NETWORK_FIRST_ORIGINS = [
  'api.open-meteo.com',
  'geocoding-api.open-meteo.com',
  'dtn.interplanet.live',
  'slm.interplanet.live',
  'api.interplanet.live',
];

// ── Install: pre-cache app shell ─────────────────────────────────────────────

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then(cache =>
      // Use individual add() so one failure doesn't abort the whole shell
      Promise.allSettled(SHELL_URLS.map(url => cache.add(url)))
    ).then(() => self.skipWaiting())
  );
});

// ── Activate: delete stale caches ────────────────────────────────────────────

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(k => k !== CACHE_VERSION).map(k => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

// ── Fetch ─────────────────────────────────────────────────────────────────────

self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  // Ignore non-GET, chrome-extension, and data: URLs
  if (request.method !== 'GET') return;
  if (url.protocol === 'chrome-extension:') return;
  if (url.protocol === 'data:') return;

  // Network-First for known API origins
  if (NETWORK_FIRST_ORIGINS.includes(url.hostname)) {
    event.respondWith(networkFirst(request));
    return;
  }

  // Network-First for share.php and api.php (dynamic server endpoints)
  if (url.pathname.includes('.php') || url.pathname.includes('/share/')) {
    event.respondWith(networkFirst(request));
    return;
  }

  // Cache-First for everything else (app shell)
  event.respondWith(cacheFirst(request));
});

// ── Strategies ────────────────────────────────────────────────────────────────

async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_VERSION);
      cache.put(request, response.clone());
    }
    return response;
  } catch(_) {
    // Offline fallback: return index.html for navigation requests
    if (request.mode === 'navigate') {
      const fallback = await caches.match('/index.html');
      if (fallback) return fallback;
    }
    return new Response('Offline — content unavailable', {
      status: 503,
      headers: { 'Content-Type': 'text/plain' },
    });
  }
}

async function networkFirst(request) {
  try {
    const response = await fetch(request);
    return response;
  } catch(_) {
    const cached = await caches.match(request);
    if (cached) return cached;
    return new Response(JSON.stringify({ error: 'offline' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
