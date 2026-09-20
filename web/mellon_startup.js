// MELLON_SILENT_START_V1. No splash, labels, timers, or minimum display time.
(() => {
  let ready = false;
  let failureReported = false;
  // Also tolerate a previously cached document containing the old splash.
  document.getElementById('loading')?.remove();
  function failed() {
    if (ready || failureReported) return;
    failureReported = true;
    // Report real failures in the console without adding a startup overlay.
    console.error('Mellon: не удалось запустить приложение. Обновите страницу.');
  }
  window.mellonStartup = { failed };
  window.addEventListener('flutter-first-frame', () => {
    ready = true;
    // Registration stays in the background, after the first Flutter frame.
    const release = document.querySelector('meta[name="mellon-build"]');
    if (release && 'serviceWorker' in navigator && window.isSecureContext) {
      navigator.serviceWorker.register(new URL('sw.js', document.baseURI), {
        updateViaCache: 'none',
      }).catch(() => {});
    }
  }, { once: true });
  window.addEventListener('error', event => {
    const src = event.target?.src || '';
    if (/\/(flutter_bootstrap|main\.dart)\.js(?:[?#]|$)/.test(src)) failed();
  }, true);
})();
