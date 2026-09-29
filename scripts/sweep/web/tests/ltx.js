'use strict';
/**
 * ltx.html end to end: setup form, every template, conference agenda and
 * fair rotation, pair delays and the v3 notice, the runner, timeline, share
 * link round trip with a stable planId, ICS export, delay matrix. planIds and
 * delays are checked against javascript/ltx/ltx-sdk.js and the spec golden
 * vectors.
 */
const fs = require('fs');
const path = require('path');
const { test, assert, eq } = require('../lib/harness');
const { REPO } = require('../lib/site');
const { checkIcs, streamText } = require('./index');
const LTX = require(path.join(REPO, 'javascript/ltx/ltx-sdk.js'));

const GOLDEN = JSON.parse(fs.readFileSync(path.join(REPO, 'spec/golden/plan-ids.json'), 'utf8'));
const PREFIX = JSON.parse(fs.readFileSync(path.join(REPO, 'spec/golden/plan-id-prefixes.json'), 'utf8'));

async function openLtx(h, site, suffix, opts) {
  const page = await h.page(opts);
  await page.goto(site.base + '/ltx.html' + (suffix || ''), { waitUntil: 'load' });
  await page.waitForFunction(() => typeof cfgFromForm === 'function' && document.querySelectorAll('.tpl-card').length > 0);
  return page;
}

module.exports = async function (h, site) {
  await test('ltx: planId in the page equals the spec golden vectors (plan-ids and prefixes)', async () => {
    const page = await openLtx(h, site);
    const bad = await page.evaluate(([g, p]) => {
      const out = [];
      for (const v of g.vectors) if (makePlanId(v.plan) !== v.planId) out.push(`${v.name}: ${makePlanId(v.plan)} != ${v.planId}`);
      for (const v of p.vectors) if (makePlanId(v.plan) !== v.planId) out.push(`prefix ${v.name}: ${makePlanId(v.plan)} != ${v.planId}`);
      return out;
    }, [GOLDEN, PREFIX]);
    eq(bad, [], 'golden mismatches');
    h.clean(page);
    await page.ctx.close();
  });

  await test('ltx: setup defaults, then every template starts a runner with the SDK planId and a full timeline', async () => {
    const page = await openLtx(h, site);
    assert(await page.locator('#setup-screen').isVisible(), 'setup visible');
    assert(await page.locator('#node-list .node-row').count() >= 2, 'default nodes');
    const tpls = await page.evaluate(() => TEMPLATES.map((t) => t.id));
    eq(await page.locator('.tpl-card').count(), tpls.length, 'one card per template');
    for (const id of tpls) {
      await page.click(`.tpl-card[data-tpl-id="${id}"]`);
      const cfg = await page.evaluate(() => cfgFromForm({ silent: true }));
      const tpl = await page.evaluate((id) => TEMPLATES.find((t) => t.id === id).cfg, id);
      eq(cfg.title, tpl.title, id + ' title');
      eq(cfg.segments.length, tpl.segments.length, id + ' segments');
      assert(LTX.validatePlan(cfg).valid, id + ' plan valid: ' + JSON.stringify(LTX.validatePlan(cfg).errors));
      await page.click('#btn-start-meeting');
      await page.waitForSelector('#runner-screen:not([hidden])');
      eq(await page.locator('#r-planid').textContent(), LTX.makePlanId(cfg), id + ' planId');
      eq(await page.locator('#r-timeline .tl-row').count(), cfg.segments.length, id + ' timeline rows');
      const nodes = cfg.nodes.length;
      eq(await page.locator('#r-delay-matrix-section').isVisible(), nodes >= 3, id + ' delay matrix shown for 3+ nodes');
      if (nodes >= 3) {
        const cells = await page.$$eval('#r-delay-matrix tbody tr', (rows) => rows.map((r) => Array.from(r.cells).map((c) => c.textContent)));
        const m = LTX.buildDelayMatrix(cfg);
        eq(cells.length, nodes * (nodes - 1), id + ' matrix rows');
        for (const [from, to, txt] of cells) {
          const a = cfg.nodes.find((n) => n.name === from), b = cfg.nodes.find((n) => n.name === to);
          const s = LTX.pairDelay(cfg, a.id, b.id);
          const want = s === 0 ? '0 s' : s < 120 ? s + ' s' : (s / 60).toFixed(1) + ' min';
          eq(txt, want, `${id} ${from}->${to}`);
        }
        assert(m, 'SDK matrix');
      }
      await page.click('#btn-runner-edit');
      await page.waitForSelector('#setup-screen:not([hidden])');
    }
    h.clean(page);
    await page.ctx.close();
  });

  await test('ltx: conference agenda labels and fair rotation (each site opens once)', async () => {
    const page = await openLtx(h, site);
    await page.click('.tpl-card[data-tpl-id="solar-system-summit"]');
    await page.click('#btn-start-meeting');
    await page.waitForSelector('#runner-screen:not([hidden])');
    const tl = await page.locator('#r-timeline').textContent();
    const shown = await page.evaluate(() => document.getElementById('runner-screen').innerText);
    const raw = shown.match(/\bltx\.[a-z_.]+/g);
    eq(raw, null, 'no raw i18n keys in the runner');
    // Banner text for an attributed TX and an async RX, from the viewer's side.
    const labels = await page.evaluate(() => {
      const c = _cfg; const seg = c.segments.find((s) => s.speaker && s.speaker !== 'N0');
      return [getBannerLabel('TX', 'host', c, seg), getBannerLabel('RX', 'host', Object.assign({}, c, { mode: 'LTX-ASYNC' }), {})];
    });
    for (const l of labels) assert(!/^ltx\./.test(l), 'banner label is not a raw key: ' + l);
    for (const label of ['Opening Address', 'Mars Field Report', 'Lunar Status Briefing', 'Jupiter Observatory Report']) {
      assert(tl.includes(label), 'agenda label ' + label);
    }
    await page.click('#btn-runner-edit');
    const cfg = await page.evaluate(() => TEMPLATES.find((t) => t.id === 'fair-roundtable').cfg);
    const tx = cfg.segments.filter((s) => s.type === 'TX');
    const n = cfg.nodes.length;
    const openers = tx.filter((_, i) => i % n === 0).map((s) => s.speaker);
    eq(openers.slice().sort(), cfg.nodes.map((x) => x.id).sort(), 'every site opens exactly one cycle');
    const sdk = LTX.buildConferenceAgenda(cfg.nodes, { cycles: 4, blockQ: 2, labels: Object.fromEntries(tx.map((s) => [s.speaker, s.label])) });
    eq(cfg.segments, sdk, 'matches SDK buildConferenceAgenda');
    h.clean(page);
    await page.ctx.close();
  });

  await test('ltx: editing a pair delay shows the v3 notice with both planIds; revert and the confirm dialog', async () => {
    const page = await openLtx(h, site);
    await page.click('.tpl-card[data-tpl-id="three-party"]');
    assert(await page.locator('#pair-delay-wrap').isVisible() || await page.locator('#pair-delay-wrap').count(), 'pair delay editor');
    assert(await page.locator('#pair-delay-v3-detail').isHidden(), 'no notice before editing');
    const v2 = await page.evaluate(() => cfgFromForm({ silent: true }));
    await page.evaluate(() => { const d = document.getElementById('pair-delay-wrap'); if (d.tagName === 'DETAILS') d.open = true; });
    await page.fill('.pair-delay-inp >> nth=0', '1234');
    await page.waitForSelector('#pair-delay-v3-detail:not([hidden])');
    const v3 = await page.evaluate(() => cfgFromForm({ silent: true }));
    eq(v3.v, 3, 'plan becomes v3');
    eq(Object.values(v3.delays), [1234], 'delays matrix');
    assert(LTX.validatePlan(v3).valid, 'v3 plan valid: ' + JSON.stringify(LTX.validatePlan(v3).errors));
    eq(await page.locator('#v3-old-id').textContent(), LTX.makePlanId(v2), 'old (v2) id');
    eq(await page.locator('#v3-new-id').textContent(), LTX.makePlanId(v3), 'new (v3) id');
    // Starting asks to confirm replacing the loaded v2 plan; dismiss keeps the setup.
    page.once('dialog', (d) => d.dismiss());
    await page.click('#btn-start-meeting');
    assert(await page.locator('#setup-screen').isVisible(), 'dismiss keeps setup');
    page.once('dialog', (d) => d.accept());
    await page.click('#btn-start-meeting');
    await page.waitForSelector('#runner-screen:not([hidden])');
    eq(await page.locator('#r-planid').textContent(), LTX.makePlanId(v3), 'runner uses the v3 id');
    // ICS for the v3 plan carries the pair delay.
    const [dl] = await Promise.all([page.waitForEvent('download'), page.click('#btn-runner-ics')]);
    const ics = await streamText(await dl.createReadStream());
    checkIcs(ics);
    assert(ics.includes('LTX-DELAY;PAIR=' + Object.keys(v3.delays)[0] + ':ONEWAY-ASSUMED=1234'), 'pair delay line');
    await page.click('#btn-runner-edit');
    await page.click('#v3-revert');
    await page.waitForSelector('#pair-delay-v3-detail[hidden]', { state: 'attached' });
    eq((await page.evaluate(() => cfgFromForm({ silent: true }))).v, 2, 'reverted to v2');
    h.clean(page);
    await page.ctx.close();
  });

  await test('ltx: share link round trip keeps the planId; ?node= links set the viewer', async () => {
    const page = await openLtx(h, site);
    await page.click('.tpl-card[data-tpl-id="short-sync"]');
    await page.fill('#f-title', 'Sweep; share, test');
    await page.click('#btn-share');
    await page.waitForSelector('#share-panel:not([hidden])');
    const url = await page.evaluate(() => location.pathname + location.search + location.hash);
    assert(/#l=[A-Za-z0-9_-]+$/.test(url), 'hash link: ' + url);
    const cfg = await page.evaluate(() => cfgFromForm({ silent: true }));
    const id = LTX.makePlanId(cfg);
    const p2 = await h.page();
    await p2.goto(site.base + url, { waitUntil: 'load' });
    await p2.waitForSelector('#runner-screen:not([hidden])');
    eq(await p2.locator('#r-planid').textContent(), id, 'planId after the round trip');
    // Starting again from the shared link (edit, start) keeps the same id.
    await p2.click('#btn-runner-edit');
    await p2.click('#btn-start-meeting');
    eq(await p2.locator('#r-planid').textContent(), id, 'planId stable through edit + start');
    // Per-node link.
    const nodeLinks = await page.$$eval('#share-node-rows a, #share-node-rows [data-url]', (els) => els.map((e) => e.getAttribute('href') || e.dataset.url));
    const n1 = await page.evaluate((c) => buildUrl(c, 'N1'), cfg);
    const p3 = await h.page();
    await p3.goto(site.base + n1, { waitUntil: 'load' });
    await p3.waitForSelector('#runner-screen:not([hidden])');
    eq(await p3.locator('#r-planid').textContent(), id, 'planId via ?node=N1');
    assert(await p3.locator('#r-viewer').isVisible(), 'viewer pill shown');
    assert((await p3.locator('#r-viewer').textContent()).includes(cfg.nodes[1].name), 'viewer is node N1');
    assert(Array.isArray(nodeLinks), 'node links listed');
    for (const p of [page, p2, p3]) { h.clean(p); await p.ctx.close(); }
  });

  await test('ltx: ICS from setup is valid, escaped and matches the SDK fields', async () => {
    const page = await openLtx(h, site);
    await page.click('.tpl-card[data-tpl-id="three-party"]');
    await page.fill('#f-title', 'Review; Mars, Moon\\Earth');
    const cfg = await page.evaluate(() => cfgFromForm({ silent: true }));
    const [dl] = await Promise.all([page.waitForEvent('download'), page.click('#btn-setup-ics')]);
    const ics = await streamText(await dl.createReadStream());
    checkIcs(ics);
    const flat = ics.replace(/\r\n /g, '');
    assert(flat.includes('\r\nUID:' + LTX.makePlanId(cfg) + '@interplanet.live\r\n'), 'UID is the planId');
    assert(flat.includes('\r\nSUMMARY:Review\\; Mars\\, Moon\\\\Earth\r\n'), 'SUMMARY escaped');
    const sdk = LTX.generateICS(cfg).replace(/\r\n /g, '');
    for (const prop of ['LTX-PLANID', 'LTX-QUANTUM', 'LTX-SEGMENT-TEMPLATE', 'LTX-MODE', 'DTSTART', 'DTEND']) {
      const re = new RegExp('\\r\\n' + prop + ':([^\\r]*)');
      eq((flat.match(re) || [])[1], ('\r\n' + sdk).match(re)[1], prop + ' equals SDK');
    }
    h.clean(page);
    await page.ctx.close();
  });
};
