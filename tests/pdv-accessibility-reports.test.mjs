import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = file => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
const app = read('app.js');
const backend = read('backend.js');
const styles = read('styles.css');
const experience = read('pdv-experience.js');
const pdvHtml = read('pdv.html');

test('interface scale has three proportional choices and Supabase persistence', () => {
  assert.match(app, /scale:'medium'/);
  assert.match(app, /\['small','medium','large'\]\.includes\(appearance\.scale\)/);
  for (const size of ['small', 'medium', 'large']) {
    assert.match(app, new RegExp(`\\['${size}'|,'${size}'|'${size}',`));
  }
  assert.match(styles, /data-scale="small"/);
  assert.match(styles, /data-scale="large"/);
  assert.match(app, /name="scale"/);
  assert.match(app, /state\.settings\.appearance=\{mode:d\.mode,palette,accent,shell,scale,font\}/);
  assert.match(backend, /theme:\s*\{\s*\.\.\.\(appearance\s*\|\|/);
  assert.match(experience, /html\[data-scale="large"\]\{font-size:18px\}/);
  assert.match(experience, /html\[data-scale="large"\] \.pdv-total strong\{font-size:36px!important\}/);
});

test('system typography offers several fonts with preview and persistence', () => {
  assert.match(app, /const fontThemes=\{/);
  for (const id of ['arial', 'source', 'inter', 'system', 'roboto', 'opensans', 'lato', 'poppins', 'nunito', 'ibmplex', 'hyperlegible']) {
    assert.match(app, new RegExp(`\\b${id}:\\{label:`));
  }
  assert.match(app, /function applyFont\(id\)/);
  assert.match(app, /function loadFontAssets\(id\)/);
  assert.match(app, /fonts\.googleapis\.com\/css2\?family=/);
  assert.match(app, /applyFont\(appearance\.font\)/);
  assert.match(app, /name="font"/);
  assert.match(app, /input\[name="font"\]/);
  assert.match(app, /font:'inter'/);
  assert.match(app, /\?String\(value\):'inter'/);
  assert.match(styles, /--app-font:Inter,system-ui/);
  assert.match(styles, /font-family:var\(--app-font\)/);
  assert.match(styles, /\.font-choice-grid\{/);
});

test('documents can be scaled up and printed as A4 right after a sale', () => {
  const documents = read('document-studio.js');
  for (const step of ['small', 'medium', 'large', 'xlarge', 'xxlarge']) {
    assert.match(documents, new RegExp(`'${step}'`));
    assert.match(styles, new RegExp(`\\.document-sheet\\.font-${step}\\{--doc-scale:`));
  }
  assert.match(documents, /Escala del documento/);
  assert.match(styles, /\.reference-document\{[^}]*font-size:calc\(11px\*var\(--doc-scale,1\)\)/);
  assert.match(styles, /height:calc\(26px\*var\(--doc-scale,1\)\)/);
  assert.match(app, /const salePrintFormats=/);
  for (const format of ['ticket', 'sale-receipt', 'zona-franca-invoice', 'sale-report']) {
    assert.match(app, new RegExp(`'${format}'`));
  }
  assert.match(app, /data-sale-print-format/);
  assert.match(app, /salePrintFormat:'ticket'/);
  assert.match(app, /data-doc-return="pos-receipt"/);
  assert.match(documents, /returnTo==='pos-receipt'\)return globalThis\.reopenSaleReceipt/);
  assert.match(app, /globalThis\.reopenSaleReceipt=reopenSaleReceipt/);
  assert.match(styles, /\.receipt-actions\{flex-wrap:wrap/);
  assert.match(documents, /fontSize:'large'/);
  assert.match(styles, /@page\{size:A4;margin:0\}/);
});

test('PDV catalog and cart scroll independently and training product has an image', () => {
  assert.match(styles, /#posCatalogRegion\{min-width:0;min-height:0;overflow:hidden\}/);
  assert.match(styles, /\.pos-product-grid,#posCartRegion\{[^}]*overflow-y:auto!important/);
  assert.match(styles, /touch-action:pan-y/);
  assert.match(app, /trainingProductImage='\.\/assets\/icon-512\.png'/);
  assert.match(app, /const productImage=product=>/);
  assert.match(backend, /image_url: '\.\/assets\/icon-512\.png'/);
});

test('clients list shows account data and offers a right-click credit menu', () => {
  const documents = read('document-studio.js');
  const backend2 = read('backend.js');
  assert.match(app, /<th>Saldo Bs<\/th><th>Saldo R\$<\/th>/);
  assert.match(app, /data-client-row="\$\{c\.id\}"/);
  assert.match(app, /function birthdateText\(value\)/);
  assert.match(app, /name="birthdate"/);
  assert.match(app, /birthdate:d\.birthdate\|\|''/);
  assert.match(backend2, /birthdate: client\.birthdate \|\| null/);
  assert.match(app, /addEventListener\('contextmenu'/);
  assert.match(app, /function clientRowMenu\(id,x,y\)/);
  for (const action of ['data-debt-flow', 'data-doc-client-debt', 'data-doc-client-statement', 'data-ledger="adjust"', 'data-client-edit']) {
    assert.match(app, new RegExp(action.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(app, /function renderDebtFlow\(\)/);
  assert.match(app, /async function registerClientPayment\(client,amount,method,note,currency='BOB'\)/);
  assert.match(app, /FloralisBackend\.registerClientPayment\(client\.id,amount,code/);
  assert.match(app, /if\(action==='payment'\)\{\s*await registerClientPayment\(c,amount,d\.paymentMethod\|\|'Efectivo',description,code\)/);
  assert.doesNotMatch(app, /if\(action==='payment'\)\{const session=ensureCashSession\(\),movement=/);
  assert.match(app, /addCashMovement\(movement\)/);
  assert.match(app, /debtAmountForm/);
  assert.match(app, /debtPaymentForm/);
  assert.match(styles, /\.context-menu\{position:fixed/);
  assert.match(styles, /\.debt-methods\{/);
  assert.match(documents, /'client-debt','Demostrativo de deuda del cliente'/);
  assert.match(documents, /function clientDebtRows\(context\)/);
  assert.match(documents, /entry\.saleId&&s\.uuid&&entry\.saleId===s\.uuid/);
});

test('Minimum is a distinct FLORALES shell and PDV theme', () => {
  assert.match(experience, /value="minimum"/);
  assert.match(experience, /Minimum FLORALES/);
  assert.match(experience, /data-shell="minimum"/);
  assert.match(experience, /pdv\.pos-theme-minimum/);
  assert.doesNotMatch(experience, /LC sistemas|LC WEB|LCsistemas/i);
});

test('remote login accepts the MARCOS username without storing a password in source', () => {
  assert.match(experience, /usernameDomain = '@floralis\.local'/);
  assert.match(experience, /principalLoginEmail = 'admin@floralis\.local'/);
  assert.match(experience, /normalized === 'marcos'/);
  assert.match(experience, /Ingrese su usuario/);
  assert.match(experience, /Digite seu usuário/);
  assert.doesNotMatch(experience, /MARCOS ou nome@empresa\.com|MARCOS o nombre@empresa\.com|Usuario o correo|Usuário ou e-mail/);
  assert.match(experience, /normalized\.includes\('@'\)/);
  assert.doesNotMatch(experience, /12345678/);
});

test('standalone PDV remembers user profiles but always asks for a password', () => {
  assert.match(experience, /floralis\.pdv\.profiles\.v1/);
  assert.match(experience, /Quem vai usar o PDV\?/);
  assert.match(experience, /Escolha seu perfil e digite apenas a senha\./);
  assert.match(experience, /profiles\.unshift\(\{userId: session\.userId \|\| session\.email, name: session\.name, email: session\.email, role: session\.role \|\| 'employee'\}\)/);
  assert.doesNotMatch(pdvHtml, /sessionStorage\.removeItem\('floralis\.pos\.unlocked'\)/, 'recargar no debe cerrar la sesión');
});

test('Minimum stays dark', () => {
  assert.match(experience, /pos-theme-minimum \.suggestions/);
  assert.match(experience, /pos-theme-minimum \.qty-stepper/);
});

test('simplified PDV keeps secondary options in the menu and checkout in the footer', () => {
  assert.match(app, /<details class="pos-menu">/);
  for (const action of ['pos-client', 'toggle-wholesale', 'pos-delivery', 'pos-notes', 'pos-settings']) assert.match(app, new RegExp(`data-action="${action}"`));
  assert.match(app, /data-pos-command="F7"/);
  assert.match(app, /class="btn primary pos-checkout" data-pos-command="F9"/);
  assert.doesNotMatch(app, /pdv-sidebar|pos-touch-shortcuts/);
  assert.match(styles, /\.pdv-simple \.pos-sale-workspace\{/);
});

test('dialogs close when tapping the backdrop, like Escape', () => {
  assert.match(app, /function dismissLayer\(\)/);
  assert.match(app, /isLayerBackdrop\(e\.target\)&&isLayerBackdrop\(layerPointerTarget\)/);
  assert.match(app, /e\.key==='Escape'&&!\$\('#layer'\)\.hidden\)\{e\.preventDefault\(\);return dismissLayer\(\)\}/);
  assert.match(styles, /\.layer-card\.modal\{max-height:calc\(100dvh - 32px\)/);
});

test('PDV shortcuts provide notebook alternatives and stay readable', () => {
  for (const shortcut of ['Alt+A', 'Alt+B', 'Alt+C', 'Alt+M', 'Alt+P', 'Alt+Q', 'Ctrl+Enter', 'Ctrl+Supr']) {
    assert.match(app, new RegExp(shortcut.replace('+', '\\+')));
  }
  assert.match(app, /e\.code\?\.startsWith\('F'\)/);
  assert.match(app, /const altCommands=/);
  assert.match(app, /checkout-key-list/);
  assert.match(styles, /Atalhos legíveis e confiáveis em notebooks/);
});

test('reports render distinct operational data sets', () => {
  const reports = [
    'Resumen', 'Rentabilidad', 'Ingresos / gastos', 'Medios de pago', 'Por vendedor',
    'Por producto', 'Horario pico', 'Ticket promedio', 'Ranking de ventas',
    'Compras por cliente', 'Movimiento de stock', 'Stock bajo', 'Valor del inventario',
    'Movimientos de caja', 'Cierres anteriores', 'Por vencer', 'Pagadas',
  ];
  for (const report of reports) assert.match(app, new RegExp(report.replace('/', '\\/')));
  assert.match(app, /function reportContent\(reportSales\)/);
  assert.match(app, /function reportProductRows\(sales\)/);
  assert.match(app, /function reportGroupRows\(rows,keyFn\)/);
  assert.match(app, /data-report-select/);
  assert.match(styles, /Central de relatórios operacionais/);
});

test('cash closing reports totals per payment method and currency', () => {
  for (const label of ['Efectivo bolivianos', 'Efectivo reales', 'PIX (R$)', 'QR (Bs)', 'Tarjeta Bs', 'Tarjeta R$']) assert.match(app, new RegExp(label.replace(/[()$]/g, '\\$&')));
  assert.match(app, /function cashClosingSummary\(closing\)/);
});

test('dismissing a receipt starts a new sale instead of keeping the charged cart', () => {
  assert.match(app, /if\(\$\('#layer \[data-action="new-sale"\]'\)\)\{closeLayer\(\);return openPos\(true\)\}/);
});

test('closing breakdown is computed server-side and stored with the closing', () => {
  const migration = read('supabase/migrations/20261012060000_cash_closing_breakdown.sql');
  assert.match(migration, /add column if not exists breakdown jsonb/);
  assert.match(migration, /public\.cash_movement_method\(description\)/);
  assert.match(migration, /closed_by_name,breakdown/);
  assert.match(backend, /breakdown: Array\.isArray\(row\.breakdown\)/);
  assert.match(app, /breakdown:remote\?\.breakdown\|\|cashBreakdown\(sessionRows\)/);
  assert.match(app, /data-closing-view=/);
});

test('cash movement method rule matches sales and debt payments', () => {
  const rule = app.match(/const cashMovementMethod=(description=>\{[^\n]*?\});/)[1];
  const method = eval(rule);
  assert.equal(method('Venta V000012 — PIX'), 'PIX');
  assert.equal(method('Venta #V1 — Tarjeta'), 'Tarjeta');
  assert.equal(method('Pago Efectivo — nota — Crediario'), 'Efectivo');
  assert.equal(method('Ajuste manual'), 'Otros ingresos');
});

test('review fixes: sale currency hydration, OTRO collision, stock alerts, history, filters', () => {
  assert.match(backend, /currency: items\[0\]\?\.currency_code === 'BRL'/);
  assert.match(read('supabase/migrations/20261011130000_open_price_products.sql'), /on conflict \(business_id,code\) do nothing/);
  assert.match(app, /ui\.productFilter==='Stock bajo'&&productTracksStock\(p\)/);
  assert.match(app, /<th>Total venta<\/th>/);
  assert.match(app, /\['Todos','Efectivo','Tarjeta','PIX','QR','Transferencia','Cuenta cliente'\]/);
});

test('expired or revoked sessions fall back to login instead of SYS-001', () => {
  const backend = read('backend.js');
  assert.match(backend, /payload\.message \|\| payload\.msg/);
  assert.match(backend, /if \(authed\) await refresh\(\)/);
  assert.match(backend, /refreshing \|\|=/);
  assert.match(backend, /dispatchEvent\(new Event\('floralis:session-expired'\)\)/);
  assert.match(app, /addEventListener\('floralis:session-expired'[\s\S]{0,120}renderLogin\('Sesión inválida'\)/);
});
