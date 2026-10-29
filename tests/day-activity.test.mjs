import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const backend = readFileSync(new URL('../backend.js', import.meta.url), 'utf8');
function dayContext(extra = {}) {
  const ctx = { Intl, Date, ui: { posDay: '2026-10-29' }, state: { sales: [], cash: [] }, locale: () => 'es-BO',
    authSession: { userId: 'admin', name: 'Admin' }, canAdmin: () => true, currencyIdSafe: c => c === 'BRL' ? 'BRL' : 'BOB',
    visibleSales: () => ctx.state.sales, ...extra };
  vm.createContext(ctx);
  vm.runInContext(app.slice(app.indexOf('function posDayKey('), app.indexOf('function saleManagementButtons(')), ctx);
  return ctx;
}
function remoteContext(fetch) {
  const saved = JSON.stringify({ userId: 'admin', businessId: 'shop', accessToken: 'test-token', expiresAt: Date.now() + 3600000 });
  const ctx = { window: { FLORALIS_CONFIG: { mode: 'supabase', supabaseUrl: 'https://example.test', supabasePublishableKey: 'public-test', loginAliases: { user: 'admin@florales.bo' } } },
    localStorage: { getItem: () => saved, setItem() {}, removeItem() {} }, fetch, Date, URL };
  vm.createContext(ctx); vm.runInContext(backend, ctx);
  return ctx.window.FloralisBackend;
}
const jsonResponse = data => ({ ok: true, status: 200, json: async () => data });

test('day boundary is midnight in Cobija even on a device in another timezone', () => {
  const ctx = dayContext();
  assert.equal(ctx.posDayKey('2026-10-29T03:59:59Z'), '2026-10-28');
  assert.equal(ctx.posDayKey('2026-10-29T04:00:00Z'), '2026-10-29');
  assert.equal(ctx.posDayKey('2026-10-30T03:59:59Z'), '2026-10-29');
});
test('day sales exclude cancelled sales, budgets and training without adding different currencies', () => {
  const ctx = dayContext();
  const sale = { date: '2026-10-29T15:00:00Z', total: 100, currency: 'BOB', type: 'Venta' };
  ctx.state.sales = [sale, { ...sale, currency: 'BRL', total: 25 }, { ...sale, status: 'cancelled' },
    { ...sale, type: 'Presupuesto' }, { ...sale, training: true }, { ...sale, date: '2026-10-28T15:00:00Z' }];
  const data = ctx.posDayData();
  assert.equal(data.total('BOB'), 100); assert.equal(data.total('BRL'), 25); assert.equal(data.active.length, 2);
  assert.equal(data.sales.length, 4);
});
test('employee daily cash view only includes their own movements', () => {
  const ctx = dayContext({ canAdmin: () => false, authSession: { userId: 'cashier', name: 'Caja' } });
  ctx.state.cash = ['Caja', 'Otro'].map(employee => ({ employee, date: '2026-10-29T15:00:00Z' }));
  assert.equal(ctx.posDayData().cash.length, 1);
  assert.equal(ctx.posDayData().cash[0].employee, 'Caja');
});
test('day refresh preserves the current cart, pending sales and other dates', async () => {
  const pending = { id: 'pending', clientSaleId: 'queued', syncStatus: 'pending', date: '2026-10-29T15:00:00Z' };
  const older = { id: 'older', date: '2026-10-28T15:00:00Z' };
  const ctx = dayContext({ closeLayer() {}, save() {}, renderPosLayer() {}, FloralisBackend: { loadDayActivity: async () => ({ sales: [{ id: 'server', date: pending.date }], cash: [] }) } });
  ctx.ui.cart = [{ id: 'rose', qty: 2 }]; ctx.ui.posView = 'day'; ctx.state.sales = [pending, older];
  await ctx.refreshPosDay();
  assert.deepEqual(ctx.ui.cart, [{ id: 'rose', qty: 2 }]);
  assert.deepEqual(Array.from(ctx.state.sales, s => s.id), ['pending', 'server', 'older']);
  assert.equal(ctx.ui.posDayLoading, false);
});
test('a delayed day response cannot overwrite a newer date or a signed-out workspace', async () => {
  let finish;
  const ctx = dayContext({ renderPosLayer() {}, save() { throw Error('must not save stale results'); }, FloralisBackend: { loadDayActivity: () => new Promise(resolve => { finish = resolve; }) } });
  const pending = ctx.refreshPosDay(); ctx.authSession = null;
  finish({ sales: [{ id: 'stale' }], cash: [] }); await pending;
  assert.equal(ctx.state.sales.length, 0);
});
test('user alias is resolved before authentication and carries no embedded password', async () => {
  const calls = [];
  const api = remoteContext(async (url, options) => {
    calls.push({ url, body: options.body });
    return jsonResponse(url.includes('/auth/') ? { user: { id: 'admin', email: 'admin@florales.bo' }, access_token: 'test-token', expires_in: 3600 } : [{ business_id: 'shop', role: 'admin', active: true }]);
  });
  const result = await api.login(' UsEr ', 'fixture-password');
  assert.equal(JSON.parse(calls[0].body).email, 'admin@florales.bo');
  assert.equal(JSON.parse(calls[0].body).password, 'fixture-password');
  assert.equal(result.role, 'admin');
});
test('daily server query pages beyond 250 sales and retains BRL received money and change', async () => {
  const urls = [];
  const sale = i => ({ id: `uuid-${i}`, sale_number: `V${i}`, created_at: '2026-10-29T15:00:00Z', total: 180,
    payment_method: 'Efectivo', payment_currency_code: 'BRL', payment_amount: 180, received_amount: 200, change_amount: 20,
    sale_items: [{ product_id: 'rose', product_name: 'Rosa', quantity: 1, unit_price: 180, currency_code: 'BRL' }] });
  const api = remoteContext(async url => {
    urls.push(url); const u = new URL(url);
    if (u.pathname.endsWith('cash_movements')) return jsonResponse([]);
    return jsonResponse(u.searchParams.get('offset') === '0' ? Array.from({ length: 250 }, (_, i) => sale(i)) : [sale(250)]);
  });
  await api.restoreSession(); const data = await api.loadDayActivity('2026-10-29');
  assert.equal(data.sales.length, 251); assert.equal(data.sales[0].currency, 'BRL');
  assert.equal(data.sales[0].received, 200); assert.equal(data.sales[0].change, 20);
  const query = new URL(urls.find(u => u.includes('/sales?'))).searchParams;
  assert.equal(query.get('business_id'), 'eq.shop');
  assert.deepEqual(query.getAll('created_at'), ['gte.2026-10-29T04:00:00.000Z', 'lt.2026-10-30T04:00:00.000Z']);
});
test('invalid calendar dates do not query the server', async () => {
  const api = remoteContext(() => { throw Error('must not query'); });
  for (const date of ['2026-02-30', 'invalid', '2026-10-29&business_id=other']) await assert.rejects(api.loadDayActivity(date), /Fecha inválida/);
});
