// MELLON_FAST_START_V1. Generated with the release's exact core file list.
const RELEASE = __MELLON_RELEASE__;
const SHELL = 'mellon-shell-v1-' + RELEASE.id;
const STATIC = 'mellon-static-v1-';
const scope = new URL(self.registration.scope);
const absolute = path => new URL(path, scope).href;
const indexURL = absolute('index.html');

function valid(response, path) {
  if (!response || response.status !== 200 || response.type === 'opaque') return false;
  const type = (response.headers.get('content-type') || '').toLowerCase();
  // Catch SPA fallback pages masquerading as missing JS, fonts or WASM.
  return path.endsWith('.html') ? type.includes('text/html') : !type.includes('text/html');
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const assets = await caches.open(STATIC + RELEASE.id);
    // Bounded concurrency, and reuse immutable files already in the HTTP cache.
    let cursor = 0;
    await Promise.all(Array.from({ length: 3 }, async () => {
      while (cursor < RELEASE.core.length) {
        const path = RELEASE.core[cursor++];
        const url = absolute(RELEASE.prefix + path);
        if (await assets.match(url)) continue;
        const response = await fetch(url, { credentials: 'omit' });
        if (!valid(response, path)) throw new Error('Incomplete Mellon release');
        await assets.put(url, response);
      }
    }));
    const response = await fetch(indexURL, { cache: 'no-cache', credentials: 'omit' });
    if (!valid(response, 'index.html')) throw new Error('Missing Mellon shell');
    const html = await response.clone().text();
    if (!html.includes('content="' + RELEASE.id + '"')) throw new Error('Release changed during install');
    await (await caches.open(SHELL)).put(indexURL, response);
    // Safe across open tabs: every document names its own versioned resources.
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    // Keep previous static versions for open documents. Browser storage quotas
    // may evict them; no private data is stored in these caches.
    await Promise.all(keys.filter(key =>
      (key.startsWith('mellon-shell-v1-') && key !== SHELL) ||
      key.startsWith('moy-prihod-offline-')
    ).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== scope.origin ||
      request.headers.has('authorization') || request.headers.has('range') ||
      !url.pathname.startsWith(scope.pathname)) return;
  const path = url.pathname.slice(scope.pathname.length);
  // Only local, versioned build resources. Never intercept Supabase, map tiles,
  // uploads, media, API calls, account requests, or URL query parameters.
  const match = /^mellon-static\/([a-f0-9]{16})\//.exec(path);
  if (match && !url.search) {
    const responsePromise = (async () => {
      const cache = await caches.open(STATIC + match[1]);
      const cached = await cache.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (valid(response, path)) {
        const copy = response.clone();
        event.waitUntil(cache.put(request, copy).catch(() => {}));
      }
      return response;
    })();
    event.respondWith(responsePromise);
    event.waitUntil(responsePromise.then(() => {}, () => {}));
    return;
  }
  // Mellon uses hash routing. Auth queries remain in the address bar; the
  // cached key is always plain index.html and contains no user-specific URL.
  if (request.mode === 'navigate' && (path === '' || path === 'index.html')) {
    event.respondWith((async () =>
      (await (await caches.open(SHELL)).match(indexURL)) || fetch(request)
    )());
  }
});
