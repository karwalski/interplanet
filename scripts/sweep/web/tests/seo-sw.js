'use strict';
/**
 * sitemap.xml, robots.txt and canonical/robots meta agree; the service worker
 * installs, every local precache URL returns 200 and is cached, and index.html
 * loads offline from the cache.
 */
const fs = require('fs');
const path = require('path');
const { test, assert, eq } = require('../lib/harness');
const { REPO } = require('../lib/site');

const ORIGIN = 'https://interplanet.live';
const DEMO = path.join(REPO, 'demo');

function pageMeta(file) {
  const html = fs.readFileSync(path.join(DEMO, file), 'utf8');
  const canon = (html.match(/<link rel="canonical" href="([^"]+)"/) || [])[1] || null;
  const robots = (html.match(/<meta name="robots" content="([^"]+)"/) || [])[1] || '';
  const ogUrl = (html.match(/<meta property="og:url"\s+content="([^"]+)"/) || [])[1] || null;
  return { canon, noindex: /noindex/i.test(robots), ogUrl };
}

module.exports = async function (h, site) {
  await test('seo: sitemap URLs are canonical, indexable, not disallowed, and exist', async () => {
    const xml = fs.readFileSync(path.join(DEMO, 'sitemap.xml'), 'utf8');
    const robots = fs.readFileSync(path.join(DEMO, 'robots.txt'), 'utf8');
    const disallow = robots.split('\n').filter((l) => /^Disallow:/i.test(l)).map((l) => l.split(':')[1].trim()).filter(Boolean);
    const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    assert(locs.length > 0, 'sitemap has URLs');
    assert(robots.includes('Sitemap: ' + ORIGIN + '/sitemap.xml'), 'robots points at the sitemap');
    for (const loc of locs) {
      assert(loc.startsWith(ORIGIN + '/'), 'absolute URL ' + loc);
      const p = loc.slice(ORIGIN.length);
      const file = p === '/' ? 'index.html' : p.slice(1);
      assert(fs.existsSync(path.join(DEMO, file)), 'file for ' + loc);
      const m = pageMeta(file);
      eq(m.canon, loc, file + ' canonical');
      assert(!m.noindex, file + ' is not noindex');
      if (m.ogUrl) eq(m.ogUrl, loc, file + ' og:url');
      for (const d of disallow) {
        const re = new RegExp('^' + d.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*'));
        assert(!re.test(p), `${loc} disallowed by ${d}`);
      }
      eq((await fetch(site.base + p)).status, 200, loc + ' served');
    }
    // Every public page with a canonical is in the sitemap unless noindex or explicitly excluded.
    const excluded = (xml.match(/Excluded:([\s\S]*?)-->/) || [])[1] || '';
    for (const f of fs.readdirSync(DEMO).filter((f) => f.endsWith('.html'))) {
      const m = pageMeta(f);
      if (!m.canon || m.noindex) continue;
      assert(locs.includes(m.canon) || excluded.includes(f), `${f} canonical ${m.canon} missing from sitemap`);
      const p = m.canon.slice(ORIGIN.length);
      eq(p === '/' ? 'index.html' : p.slice(1), f, f + ' canonical points at itself');
    }
  });

  await test('seo: robots.txt disallowed pages are not indexable-with-canonical by mistake', async () => {
    const robots = fs.readFileSync(path.join(DEMO, 'robots.txt'), 'utf8');
    for (const l of robots.split('\n').filter((l) => /^Disallow:\s*\/[a-z-]+\.html/i.test(l))) {
      const f = l.split(':')[1].trim().slice(1);
      const m = pageMeta(f);
      assert(!m.canon, `${f} is disallowed but declares canonical ${m.canon}`);
    }
  });

  await test('service worker: installs, precache URLs return 200 and are cached, index works offline', async () => {
    const sw = fs.readFileSync(path.join(DEMO, 'sw.js'), 'utf8');
    const list = eval('(' + sw.match(/const SHELL_URLS = (\[[\s\S]*?\]);/)[1] + ')');
    const local = list.filter((u) => u.startsWith('/'));
    for (const u of local) eq((await fetch(site.base + u)).status, 200, 'precache ' + u);
    // Every same-origin script and stylesheet index.html loads is precached (else offline breaks).
    const html = fs.readFileSync(path.join(DEMO, 'index.html'), 'utf8');
    const refs = [...html.matchAll(/<(?:script[^>]+src|link[^>]+rel="stylesheet"[^>]+href)="([^"]+)"/g)].map((m) => m[1])
      .filter((u) => !/^https?:/.test(u)).map((u) => '/' + u.replace(/^\//, ''));
    for (const r of refs) assert(local.includes(r), `index.html loads ${r} but sw.js does not precache it`);
    const version = sw.match(/CACHE_VERSION = '([^']+)'/)[1];

    const { SKIP_SPLASH } = require('./index');
    const page = await h.page({ serviceWorkers: 'allow', init: SKIP_SPLASH });
    await page.goto(site.base + '/', { waitUntil: 'load' });
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForFunction((v) => caches.has(v), version, { timeout: 15000 });
    const cached = await page.evaluate(async ([v, urls]) => {
      const c = await caches.open(v);
      const out = [];
      for (const u of urls) if (!(await c.match(u))) out.push(u);
      return out;
    }, [version, local]);
    eq(cached, [], 'local precache URLs missing from the cache');
    await page.ctx.setOffline(true);
    await page.reload({ waitUntil: 'load' });
    await page.waitForFunction(() => window.STATE && window.PlanetTime, null, { timeout: 10000 });
    await page.evaluate(() => addPlanet('mars', 0, null, null, { silent: true }));
    assert(await page.locator('.city-col').count() === 1, 'app works offline');
    await page.ctx.close();
  });
};
