/*
  Alfaeq Yemen offline service worker.

  Purpose: after a user opens the app once, every static file the Flutter
  engine needs (engine, canvaskit, main.dart.js, fonts, images) is cached on
  the device. The app then starts with no internet at all — which is what a
  user who has no data plan expects.

  Strategy:
  - Navigations: network first, fall back to the cached app shell (index.html)
    so opening the site while offline still boots the app.
  - Same-origin GET (static assets): cache first, then fill the cache in the
    background. Assets are content-addressed by the build, so they are safe to
    keep.
  - Cross-origin (e.g. Supabase API): never cached, always live. Data needs
    the network; the app shell does not.
*/

const VERSION = 'alfaeq-offline-v2';
const CACHE = VERSION;
// الملفات التي تضمن إقلاع التطبيق بدون إنترنت بعد أول زيارة.
const APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './logo.png',
  './main.dart.js',
  './flutter.js',
  './flutter_bootstrap.js',
  './assets/FontManifest.json',
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/fonts/NotoSansArabic-Regular.ttf',
  './assets/fonts/fallback/Roboto-Regular.ttf',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then(async (cache) => {
      // نتجاهل أي ملف غير موجود حتى لا يفشل التثبيت بالكامل.
      await Promise.all(APP_SHELL.map((url) => cache.add(url).catch(() => undefined)));
    }).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

function isStaticAsset(url) {
  return /\.(js|mjs|json|wasm|css|html|png|jpg|jpeg|gif|svg|webp|ico|woff2?|ttf|otf|mp3|mp4)$/i.test(url.pathname)
    || url.pathname.includes('/canvaskit/')
    || url.pathname.includes('/assets/');
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(request, { ignoreSearch: false });
  if (cached) return cached;
  const response = await fetch(request);
  if (response && response.ok && response.type === 'basic') {
    cache.put(request, response.clone()).catch(() => undefined);
  }
  return response;
}

async function networkFirstNavigation(request) {
  const cache = await caches.open(CACHE);
  try {
    const response = await fetch(request);
    if (response && response.ok) {
      cache.put(request, response.clone()).catch(() => undefined);
      cache.put('./index.html', response.clone()).catch(() => undefined);
    }
    return response;
  } catch (error) {
    const cached = (await cache.match(request)) || (await cache.match('./index.html')) || (await cache.match('./'));
    if (cached) return cached;
    throw error;
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // Supabase/API stays live.

  if (request.mode === 'navigate') {
    event.respondWith(networkFirstNavigation(request));
    return;
  }
  if (isStaticAsset(url)) {
    event.respondWith(cacheFirst(request).catch(() => fetch(request)));
  }
});

// Allow the page to warm the cache once the engine has started.
self.addEventListener('message', (event) => {
  if (event.data !== 'alfaeq-warm-cache') return;
  caches.open(CACHE).then((cache) => cache.addAll(APP_SHELL).catch(() => undefined));
});
