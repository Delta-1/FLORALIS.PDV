import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const backend = readFileSync(new URL('../backend.js', import.meta.url), 'utf8');
const pdvExperience = readFileSync(new URL('../pdv-experience.js', import.meta.url), 'utf8');
const migration = readFileSync(
  new URL('../supabase/migrations/20260821_reports_documents_tutorials.sql', import.meta.url),
  'utf8',
);

test('Cuenta cliente can be selected before a client is chosen', () => {
  assert.match(app, /function choosePayment\(value,focus=false\)/);
  assert.match(app, /value==='Cuenta cliente'&&!ui\.posClient.*posClientPicker\('payment'\)/);
  assert.doesNotMatch(app, /Cuenta cliente'&&!ui\.posClient\?'disabled'/);
});

test('customer picker returns to payment and supports search', () => {
  assert.match(app, /function posClientPicker\(returnTo=ui\.clientPickerReturn\|\|'pos'\)/);
  assert.match(app, /id="posClientSearch"/);
  assert.match(app, /function finishClientSelection\(clientId\).*ui\.posClient=clientId.*destination==='payment'.*paymentLayer\(\)/s);
});

test('PDV keeps customer search, creation and selection inside the sale', () => {
  assert.match(pdvExperience, /function ensureClientStrip\(\)/);
  assert.match(pdvExperience, /data-pdv-client-search/);
  assert.match(pdvExperience, /data-pdv-client-new/);
  assert.match(pdvExperience, /data-pdv-client-clear/);
  assert.match(pdvExperience, /function enhanceClientPicker\(\)/);
  assert.match(pdvExperience, /window\.finishClientSelection\?\.\(''\)/);
  assert.match(app, /Al guardar, el cliente quedará seleccionado en esta venta/);
});

test('checkout refuses a customer-account sale without a customer', () => {
  assert.match(app, /payment==='Cuenta cliente'&&!client.*posClientPicker\('payment'\)/s);
});

test('sale payload sends the selected customer to Supabase', () => {
  assert.match(app, /clientId:client\?\.id\|\|null/);
  assert.match(backend, /registerSale/);
  assert.match(backend, /p_client_id:\s*payload\.clientId/);
});

test('database RPC records customer-account sales in the ledger', () => {
  assert.match(migration, /p_payment_method='Cuenta cliente'/);
  assert.match(migration, /record_client_movement_v2\(p_business_id,p_client_id,'debit',total_value/);
  assert.match(migration, /update clients set purchases=purchases\+1,total_purchased=total_purchased\+total_value/);
});

test('database stock validation follows the PDV configuration', () => {
  const fixMigration = readFileSync(
    new URL('../supabase/migrations/20260903_fix_sale_stock_account_sync.sql', import.meta.url),
    'utf8',
  );
  assert.match(fixMigration, /drop constraint if exists products_stock_check/);
  assert.match(fixMigration, /app_config->'options'->>'blockNoStock'/);
  assert.match(fixMigration, /block_no_stock:=coalesce\(block_no_stock,true\)/);
  assert.match(fixMigration, /block_no_stock and p\.stock<qty/);
  assert.match(fixMigration, /record_client_movement_v2\(p_business_id,p_client_id,'debit',total_value/);
});

test('online business errors do not become fake offline sales', () => {
  assert.match(backend, /error\.status = response\.status/);
  assert.match(app, /retryableSaleSyncError/);
  assert.match(app, /if\(!retryableSaleSyncError\(error\)\)/);
  assert.match(app, /La venta no fue registrada/);
});

test('local stock mirrors the configured negative-stock behavior', () => {
  assert.match(app, /state\.settings\.options\.blockNoStock\?Math\.max\(0,p\.stock-i\.qty\):p\.stock-i\.qty/);
});
