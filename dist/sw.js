const CACHE = 'floralis-shell-v50';
const CORE = [
  './', './index.html', './pdv.html', './styles.css?v=41', './config.js?v=17',
  './backend.js?v=33', './app.js?v=44', './document-studio.js?v=33', './pwa.js?v=17', './import-wizard.js?v=18', './pdv-experience.js?v=28', './native-shell.js?v=1', './manifest.webmanifest',
  './assets/floralis-logo.png', './assets/floralis-mark.png',
  './assets/icon-512.png', './assets/icon-maskable-192.png', './assets/icon-maskable-512.png',
  './assets/apple-touch-icon.png', './assets/favicon.ico'
];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key.startsWith('floralis-shell-') && key !== CACHE).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', event => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const {request} = event;
  if (request.method !== 'GET' || new URL(request.url).origin !== location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then(response => {
          if (response.ok) caches.open(CACHE).then(cache => cache.put(request, response.clone()));
          return response;
        })
        .catch(async () => {
          const cachedPage = await caches.match(request, {ignoreSearch: true});
          if (cachedPage) return cachedPage;
          return caches.match(request.url.includes('/pdv') ? './pdv.html' : './index.html');
        })
    );
    return;
  }

  event.respondWith(
    caches.match(request, {ignoreSearch: true}).then(cached => {
      const refresh = fetch(request).then(response => {
        if (response.ok) caches.open(CACHE).then(cache => cache.put(request, response.clone()));
        return response;
      }).catch(() => cached);
      return cached || refresh;
    })
  );
});
