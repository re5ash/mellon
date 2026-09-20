{{flutter_js}}
{{flutter_build_config}}

// MELLON_FAST_START_V1. Each release has its own immutable asset directory.
// Also works at the root during ordinary flutter run/build.
(() => {
  const base = new URL('./', document.currentScript?.src || document.baseURI).href;
  const config = {
    canvasKitBaseUrl: new URL('canvaskit/', base).href,
    assetBase: base,
    entrypointBaseUrl: base,
  };
  const fail = () => window.mellonStartup?.failed();
  _flutter.loader.load({
    config,
    onEntrypointLoaded: async (initializer) => {
      try {
        const runner = await initializer.initializeEngine(config);
        await runner.runApp();
      } catch (_) { fail(); }
    },
  }).catch(fail);
})();
