(() => {
  const installButton = document.getElementById('pwaInstallButton');
  const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  const isIOS = /iphone|ipad|ipod/i.test(window.navigator.userAgent);
  let installPrompt = null;

  function setInstallVisible(visible) {
    if (!installButton) return;
    installButton.hidden = !visible || isStandalone();
  }

  function closeGuide() {
    document.getElementById('pwaInstallGuide')?.remove();
  }

  function showGuide(title, text) {
    closeGuide();
    const guide = document.createElement('section');
    guide.id = 'pwaInstallGuide';
    guide.className = 'pwa-install-guide';
    guide.setAttribute('role', 'dialog');
    guide.setAttribute('aria-modal', 'true');
    guide.innerHTML = `
      <div class="pwa-guide-card">
        <img src="./assets/icon-maskable-192.png" alt="Ícone FLORALES">
        <div><small>INSTALAR APLICATIVO</small><strong>${title}</strong><p>${text}</p></div>
        <button type="button" aria-label="Fechar instruções">×</button>
      </div>`;
    guide.querySelector('button').addEventListener('click', closeGuide);
    guide.addEventListener('click', event => { if (event.target === guide) closeGuide(); });
    document.body.appendChild(guide);
  }

  async function install() {
    if (isStandalone()) {
      showGuide('FLORALES já está instalado', 'Abra o sistema pelo ícone disponível na tela inicial ou no menu de aplicativos.');
      return false;
    }

    if (installPrompt) {
      installPrompt.prompt();
      const {outcome} = await installPrompt.userChoice;
      installPrompt = null;
      setInstallVisible(false);
      return outcome === 'accepted';
    }

    if (isIOS) {
      showGuide('Adicionar à Tela de Início', 'No Safari, toque em Compartilhar e depois em “Adicionar à Tela de Início”.');
      return false;
    }

    showGuide('Instalar FLORALES', 'Abra o menu do navegador e escolha “Instalar aplicativo” ou “Adicionar à tela inicial”.');
    return false;
  }

  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    installPrompt = event;
    setInstallVisible(true);
  });

  window.addEventListener('appinstalled', () => {
    installPrompt = null;
    setInstallVisible(false);
    closeGuide();
  });

  installButton?.addEventListener('click', install);
  document.addEventListener('click', event => {
    const trigger = event.target.closest?.('[data-action="install-pwa"]');
    if (!trigger) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    install();
  }, true);
  if (isIOS && !isStandalone()) setInstallVisible(true);

  if ('serviceWorker' in navigator && location.protocol !== 'file:') {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('./sw.js').then(registration => {
        registration.update().catch(() => {});
      }).catch(() => {});
    }, {once: true});
  }

  window.FloralisPWA = {install, isStandalone};
})();
