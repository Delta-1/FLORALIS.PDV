(() => {
  const params = new URLSearchParams(location.search);
  const capacitor = globalThis.Capacitor;
  const nativePlatform = globalThis.FLORALIS_NATIVE_APP?.platform
    || (capacitor?.isNativePlatform?.() ? capacitor.getPlatform?.() || 'mobile' : '')
    || params.get('native');
  if (!nativePlatform) return;

  document.documentElement.dataset.nativeApp = nativePlatform;
  globalThis.FLORALIS_NATIVE_APP ||= Object.freeze({ platform: nativePlatform, container: 'capacitor' });

  const appPlugin = capacitor?.Plugins?.App;
  const printerPlugin = capacitor?.Plugins?.Printer;
  if (capacitor?.isNativePlatform?.() && printerPlugin?.printWebView) {
    globalThis.print = async () => {
      try {
        await printerPlugin.printWebView({ name: document.title || 'FLORALIS PDV ERP' });
      } finally {
        globalThis.dispatchEvent(new Event('afterprint'));
      }
    };
  }
  appPlugin?.addListener?.('backButton', () => {
    const layer = document.getElementById('layer');
    if (layer && !layer.hidden) {
      const contextualBack = layer.querySelector('[data-action="back-pos"], [data-action="back-client-picker"], [data-action="back-client"]');
      (contextualBack || layer.querySelector('[data-action="close-layer"]'))?.click();
      return;
    }
    if (history.length > 1) history.back();
    else appPlugin.minimizeApp?.();
  });
})();
