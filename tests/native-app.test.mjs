import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = file => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');

test('native packages share the existing ERP and PDV code', () => {
  const prepare = read('scripts/prepare-native.mjs');
  assert.match(prepare, /'index\.html'/);
  assert.match(prepare, /'app\.js'/);
  assert.match(prepare, /'backend\.js'/);
  assert.match(prepare, /'document-studio\.js'/);
});

test('desktop shell keeps renderer isolated and local storage origin stable', () => {
  const desktop = read('native/electron/main.cjs');
  assert.match(desktop, /APP_PORT = 41731/);
  assert.match(desktop, /contextIsolation: true/);
  assert.match(desktop, /nodeIntegration: false/);
  assert.match(desktop, /sandbox: true/);
  assert.match(desktop, /127\.0\.0\.1/);
});

test('native ERP opens the PDV inline and can return to ERP', () => {
  const app = read('app.js');
  const experience = read('pdv-experience.js');
  assert.match(app, /native-back-erp/);
  assert.match(app, /Volver al ERP/);
  assert.match(experience, /globalThis\.FLORALIS_NATIVE_APP/);
});

test('Android uses the native print service for receipts and reports', () => {
  const shell = read('native-shell.js');
  const packageJson = read('package.json');
  assert.match(packageJson, /@capgo\/capacitor-printer/);
  assert.match(shell, /printerPlugin\.printWebView/);
  assert.match(shell, /afterprint/);
});

test('GitHub builds Windows executables and Android APK', () => {
  const workflow = read('.github/workflows/native-build.yml');
  const packageJson = read('package.json');
  assert.match(packageJson, /electron-builder/);
  assert.match(packageJson, /--publish never/);
  assert.match(packageJson, /FLORALIS-PDV-ERP-Setup/);
  assert.match(packageJson, /FLORALIS-PDV-ERP-Portable/);
  assert.match(workflow, /npm run desktop:build/);
  assert.match(workflow, /branches:\s+\- main/);
  assert.match(workflow, /release\/\*\.exe/);
  assert.match(workflow, /assembleDebug/);
  assert.match(workflow, /app-debug\.apk/);
});

test('public frontend configuration never contains a Supabase service role key', () => {
  const config = read('config.js');
  assert.doesNotMatch(config, /supabaseServiceRoleKey|sb_secret_/i);
  assert.match(config, /supabasePublishableKey/);
});
