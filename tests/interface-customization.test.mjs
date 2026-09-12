import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const [app, styles, experience] = await Promise.all([
  readFile(new URL('../app.js', import.meta.url), 'utf8'),
  readFile(new URL('../styles.css', import.meta.url), 'utf8'),
  readFile(new URL('../pdv-experience.js', import.meta.url), 'utf8')
]);

test('Inter is the default typography with offline system fallbacks', () => {
  assert.match(app, /scale:'medium',font:'inter'/);
  assert.match(app, /Inter,system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif/);
  assert.match(styles, /--app-font:Inter,system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif/);
});

test('ERP sidebar expands on desktop hover and keeps mobile touch behavior', () => {
  assert.match(styles, /@media\(min-width:721px\)[\s\S]*\.nex-navbar:hover[\s\S]*width:236px/);
  assert.match(styles, /\.nex-navbar:hover~\.nex-workspace[\s\S]*margin-left:236px/);
  assert.match(app, /matchMedia\('\(min-width:721px\)'\)\.matches/);
  assert.match(styles, /@media\(max-width:720px\)[\s\S]*\.nex-navbar\.open/);
});

test('PDV personalization is available inside the terminal and ERP settings', () => {
  assert.match(app, /data-action="pos-customize"/);
  assert.match(app, /id="posAppearanceForm"/);
  assert.match(app, /name="mode"/);
  assert.match(app, /name="palette"/);
  assert.match(app, /name="borders"/);
  assert.match(app, /data-pos-palette=/);
  assert.match(app, /pos-border-\$\{posBorderId\(layout\.borders\)\}/);
  assert.match(app, /f\.id==='posLayoutForm'\|\|f\.id==='posAppearanceForm'/);
  assert.match(experience, /#posAppearanceForm select\[name="palette"\]/);
});

test('PDV palettes, independent dark mode and reinforced borders are styled', () => {
  for (const color of ['blue', 'green', 'purple', 'orange', 'red', 'floralis']) {
    assert.match(styles, new RegExp(`data-pos-palette="${color}"`));
  }
  assert.match(styles, /\.pdv\.pos-mode-dark/);
  assert.match(styles, /\.pdv\.pos-mode-light/);
  assert.match(styles, /\.pdv\.pos-border-strong/);
});

test('Floralis supports BOB, BRL and USD directly in the PDV', () => {
  for (const currency of ['BOB', 'BRL', 'USD']) assert.match(app, new RegExp(`${currency}:`));
  assert.match(app, /data-pos-currency/);
  assert.match(app, /id="currencyForm"/);
  assert.match(app, /currency:saleCurrency/);
  assert.match(styles, /\.pos-currency-switch/);
});
