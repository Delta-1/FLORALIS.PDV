import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const [app, backend, config, migration, separateColumnsMigration] = await Promise.all([
  readFile(new URL('../app.js', import.meta.url), 'utf8'),
  readFile(new URL('../backend.js', import.meta.url), 'utf8'),
  readFile(new URL('../config.js', import.meta.url), 'utf8'),
  readFile(new URL('../supabase/migrations/20260918143000_precise_currency_accounting.sql', import.meta.url), 'utf8'),
  readFile(new URL('../supabase/migrations/20260921170000_separate_bob_brl_columns.sql', import.meta.url), 'utf8'),
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

test('PDV reference editor does not mix reporting currencies', () => {
  assert.match(app, /safeBobQuote/);
  assert.match(app, /BRL:1\/safeBobQuote\(brlInBob\)/);
  assert.match(app, /Caja e informes no hacen conversiones/);
  assert.match(app, /Los informes nunca convierten una moneda a la otra/);
});

test('reporting amounts are persisted in independent BOB and BRL columns', () => {
  assert.match(separateColumnsMigration, /amount_bob/);
  assert.match(separateColumnsMigration, /amount_brl/);
  assert.match(separateColumnsMigration, /sync_sale_report_currency_columns/);
  assert.match(separateColumnsMigration, /sync_cash_report_currency_columns/);
  assert.match(separateColumnsMigration, /not \(amount_bob > 0 and amount_brl > 0\)/);
});
