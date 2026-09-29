'use strict';
/**
 * Every translation key the pages use (data-i18n* attributes and literal
 * t('...') / getT('...') calls) exists in the English table, so no raw key is
 * ever shown; per-language coverage of those keys is reported.
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { test, eq } = require('../lib/harness');
const { REPO } = require('../lib/site');

const DEMO = path.join(REPO, 'demo');

function loadI18n() {
  const html = { setAttribute() {} };
  const ctx = {
    window: {}, localStorage: { getItem() { return null; }, setItem() {} },
    navigator: { languages: ['en'] }, document: { documentElement: html, querySelectorAll() { return []; } },
    Intl,
  };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(DEMO, 'assets/i18n.js'), 'utf8'), ctx);
  return ctx.window.I18N;
}

function usedKeys() {
  const keys = new Map();
  const add = (k, where) => { if (/^[a-z0-9_]+(\.[a-zA-Z0-9_]+)+$/.test(k)) keys.set(k, where); };
  for (const f of fs.readdirSync(DEMO).filter((f) => /\.(html|js)$/.test(f))) {
    const src = fs.readFileSync(path.join(DEMO, f), 'utf8');
    for (const m of src.matchAll(/data-i18n(?:-html|-placeholder|-aria)?="([^"]+)"/g)) add(m[1], f);
    for (const m of src.matchAll(/data-i18n-attr="([^"]+)"/g)) for (const p of m[1].split(',')) add(p.split(':')[1].trim(), f);
    for (const m of src.matchAll(/\b(?:t|getT|I18N\.t)\(\s*'([^'$`{}]+)'/g)) add(m[1], f);
  }
  return keys;
}

module.exports = async function () {
  await test('i18n: every key used by the pages exists in English; coverage per language', async () => {
    const I = loadI18n();
    const keys = usedKeys();
    I.setLocale('en');
    // ltx.html's getT falls back to its inline English table for keys i18n.js lacks.
    const ltx = fs.readFileSync(path.join(DEMO, 'ltx.html'), 'utf8');
    const fb = ltx.slice(ltx.indexOf('const FB = {'), ltx.indexOf('};', ltx.indexOf('const FB = {')));
    const ltxFallback = new Set([...fb.matchAll(/'([a-z0-9_.]+)':/g)].map((m) => m[1]));
    const missing = [...keys].filter(([k, f]) => I.t(k) === k && !(f === 'ltx.html' && ltxFallback.has(k)))
      .map(([k, f]) => `${k} (${f})`);
    const cov = [];
    for (const lang of I.SUPPORTED_LANGS.filter((l) => l !== 'en')) {
      I.setLocale('en');
      const en = new Map([...keys.keys()].map((k) => [k, I.t(k)]));
      I.setLocale(lang);
      const same = [...keys.keys()].filter((k) => I.t(k) === en.get(k) && /[a-z]{4,}/i.test(en.get(k))).length;
      cov.push(`${lang} ${Math.round(100 * (keys.size - same) / keys.size)}%`);
    }
    console.log(`  (info) ${keys.size} keys used; translated share per language: ${cov.join(', ')}`);
    eq(missing, [], 'keys missing from the English table');
  });
};
