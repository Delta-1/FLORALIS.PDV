import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const [app, index, pdv] = await Promise.all([
  readFile(new URL('../app.js', import.meta.url), 'utf8'),
  readFile(new URL('../index.html', import.meta.url), 'utf8'),
  readFile(new URL('../pdv.html', import.meta.url), 'utf8'),
]);

test('cash can be opened and closed from both ERP and PDV', () => {
  assert.match(app, /data-action="cash-open"/);
  assert.match(app, /data-action="cash-close"/);
  assert.match(app, /data-action="pos-cash-session"/);
  assert.match(app, /'pos-cash-open'/);
  assert.match(app, /'pos-cash-close'/);
  assert.match(app, /Abra la caja antes de registrar una venta/);
  assert.doesNotMatch(app.match(/async function startAuthenticated[\s\S]*?function renderLogin/)?.[0] || '', /ensureCashSession\(\)/);
});

test('PWA installation lives in settings instead of floating over the UI', () => {
  assert.doesNotMatch(index, /id="pwaInstallButton"/);
  assert.doesNotMatch(pdv, /id="pwaInstallButton"/);
  assert.match(app, /\['app','Instalar aplicativo'\]/);
  assert.match(app, /data-action="install-pwa"/);
  assert.match(app, /La instalación queda aquí para no ocupar espacio en el PDV/);
});
