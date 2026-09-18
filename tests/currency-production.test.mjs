import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const [app, backend, config, migration] = await Promise.all([
  readFile(new URL('../app.js', import.meta.url), 'utf8'),
  readFile(new URL('../backend.js', import.meta.url), 'utf8'),
  readFile(new URL('../config.js', import.meta.url), 'utf8'),
  readFile(new URL('../supabase/migrations/20260918143000_precise_currency_accounting.sql', import.meta.url), 'utf8'),
]);

test('production frontend points to Supabase without privileged credentials', () => {
  assert.match(config, /mode: 'supabase'/);
  assert.match(config, /sb_publishable_/);
  assert.doesNotMatch(config, /service_role/i);
});

test('sale, currency and cash movement are committed atomically', () => {
  assert.match(backend, /rpc\/register_sale_v2/);
  assert.doesNotMatch(backend.match(/async function registerSale[\s\S]*?async function saveGeneratedDocument/)?.[0] || '', /set_sale_currency/);
  assert.match(migration, /create or replace function public\.register_sale_v2/);
  assert.match(migration, /currency total mismatch/);
  assert.match(migration, /insert into cash_movements[\s\S]*currency_code,exchange_rate,display_amount/);
  assert.match(migration, /revoke execute on function public\.set_sale_currency/);
});

test('PDV rate editor uses the intuitive BOB quote and preserves history', () => {
  assert.match(app, /safeBobQuote/);
  assert.match(app, /BRL:1\/safeBobQuote\(brlInBob\)/);
  assert.match(app, /Los informes anteriores no cambian/);
  assert.match(app, /Cada venta guarda la cotización utilizada/);
});
