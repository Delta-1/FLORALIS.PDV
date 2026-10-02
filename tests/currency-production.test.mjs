import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const [app, backend, config, migration, paymentMigration, separateColumnsMigration] = await Promise.all([
  readFile(new URL('../app.js', import.meta.url), 'utf8'),
  readFile(new URL('../backend.js', import.meta.url), 'utf8'),
  readFile(new URL('../config.js', import.meta.url), 'utf8'),
  readFile(new URL('../supabase/migrations/20261001153000_native_dual_currency_cash_sessions.sql', import.meta.url), 'utf8'),
  readFile(new URL('../supabase/migrations/20261002004212_payment_currency_without_exchange.sql', import.meta.url), 'utf8'),
  readFile(new URL('../supabase/migrations/20260921170000_separate_bob_brl_columns.sql', import.meta.url), 'utf8'),
]);

test('production frontend points to Supabase without privileged credentials', () => {
  assert.match(config, /mode: 'supabase'/);
  assert.match(config, /sb_publishable_/);
  assert.doesNotMatch(config, /service_role/i);
});

test('sale, currency and cash movement are committed atomically', () => {
  assert.match(backend, /rpc\/register_sale_v4/);
  assert.doesNotMatch(backend.match(/async function registerSale[\s\S]*?async function saveGeneratedDocument/)?.[0] || '', /set_sale_currency/);
  assert.match(paymentMigration, /create or replace function public\.register_sale_v4/);
  assert.match(paymentMigration, /p_payment_currency_code not in \('BOB','BRL'\)/);
  assert.match(paymentMigration, /insert into public\.cash_movements/);
  assert.match(paymentMigration, /cash_session_id,terminal_id/);
  assert.match(paymentMigration, /revoke all on function public\.register_sale_v4/);
  assert.match(paymentMigration, /currency_code,unit_cost_bob,unit_cost_brl[\s\S]*'BOB'/);
});

test('PDV reference editor does not mix reporting currencies', () => {
  assert.match(app, /dualCurrencyNativePricing:true/);
  assert.match(app, /Ningún precio, cobro, saldo o informe se calcula mediante cotización/);
  assert.match(app, /Solo como anotación administrativa\. No altera ningún valor del sistema/);
  assert.doesNotMatch(app, /function convertMoney/);
  assert.doesNotMatch(backend, /p_exchange_rate/);
});

test('native prices and persistent cash sessions are part of the production migration', () => {
  for (const column of ['price_bob', 'price_brl', 'wholesale_bob', 'wholesale_brl']) assert.match(migration, new RegExp(column));
  assert.match(migration, /create table if not exists public\.cash_sessions/);
  assert.match(migration, /create table if not exists public\.cash_closings/);
  assert.match(migration, /create or replace function public\.open_cash_session_v1/);
  assert.match(migration, /create or replace function public\.close_cash_session_v1/);
});

test('reporting amounts are persisted in independent BOB and BRL columns', () => {
  assert.match(separateColumnsMigration, /amount_bob/);
  assert.match(separateColumnsMigration, /amount_brl/);
  assert.match(separateColumnsMigration, /sync_sale_report_currency_columns/);
  assert.match(separateColumnsMigration, /sync_cash_report_currency_columns/);
  assert.match(separateColumnsMigration, /not \(amount_bob > 0 and amount_brl > 0\)/);
});
