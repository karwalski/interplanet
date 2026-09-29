'use strict';
/**
 * dashboard (from #l= and from ?session= via api/ltx.php, relay health),
 * distance, events, clock, widget, topics, related-work, playground, v1:
 * each page's computed values against planet-time.js.
 */
const path = require('path');
const { test, assert, eq } = require('../lib/harness');
const { REPO } = require('../lib/site');
const LTX = require(path.join(REPO, 'javascript/ltx/ltx-sdk.js'));
const PT = require(path.join(REPO, 'demo/planet-time.js'));

function livePlan() {
  const start = new Date(Date.now() - 5 * 60000);
  start.setUTCSeconds(0, 0);
  return {
    v: 2, title: 'Sweep dashboard', start: start.toISOString(), quantum: 5, mode: 'LTX-LIVE',
    nodes: [
      { id: 'N0', name: 'Earth HQ', role: 'HOST', delay: 0, location: 'earth' },
      { id: 'N1', name: 'Mars Base', role: 'PARTICIPANT', delay: 1240, location: 'mars' },
      { id: 'N2', name: 'Lunar Base', role: 'PARTICIPANT', delay: 2, location: 'moon' },
    ],
    segments: [{ type: 'PLAN_CONFIRM', q: 2 }, { type: 'TX', q: 3 }, { type: 'RX', q: 3 }, { type: 'BUFFER', q: 1 }],
  };
}
const b64url = (s) => Buffer.from(s, 'utf8').toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function checkDashboard(page, plan) {
  await page.waitForSelector('#session-header:not([style*="none"])');
  eq(await page.locator('#session-title-text').textContent(), plan.title, 'title');
  const meta = await page.locator('#session-plan-id').textContent();
  assert(meta.includes('Plan ID: ' + LTX.makePlanId(plan)), 'plan id: ' + meta);
  eq(await page.locator('#session-status-pill').textContent(), 'Live', 'status');
  eq(await page.locator('#session-mode-pill').textContent(), 'LTX-LIVE', 'mode');
  const nodes = await page.locator('#nodes-card').textContent();
  for (const n of plan.nodes) assert(nodes.includes(n.name), 'node ' + n.name);
}

module.exports = async function (h, site) {
  await test('dashboard: from a #l= hash (Live session, planId, nodes)', async () => {
    const plan = livePlan();
    const page = await h.page();
    await page.goto(site.base + '/dashboard.html#l=' + b64url(JSON.stringify(plan)), { waitUntil: 'load' });
    await checkDashboard(page, plan);
    h.clean(page);
    await page.ctx.close();
  });

  await test('dashboard: from ?session= via api/ltx.php, with ?relay= health from relay-server.php', async () => {
    const plan = Object.assign(livePlan(), { title: 'Sweep dashboard via API' });
    const r = await fetch(site.base + '/api/ltx.php?action=session', { method: 'POST', body: JSON.stringify(plan) });
    const j = await r.json();
    eq(j.stored, true, 'stored');
    const page = await h.page();
    const relay = site.base + '/relay-server.php/relay';
    await page.goto(site.base + '/dashboard.html?session=' + encodeURIComponent(j.plan_id) + '&relay=' + encodeURIComponent(relay), { waitUntil: 'load' });
    await checkDashboard(page, plan);
    await page.waitForFunction(() => /Online/.test(document.getElementById('relay-card').textContent));
    const relayTxt = await page.locator('#relay-card').textContent();
    assert(/\d+ frames/.test(relayTxt), 'queue count shown: ' + relayTxt);
    await page.click('#refresh-btn');
    eq(await page.locator('#session-title-text').textContent(), plan.title, 'refresh keeps the session');
    h.clean(page);
    // Unknown session: an error message, not a crash.
    const p2 = await h.page();
    await p2.goto(site.base + '/dashboard.html?session=LTX-20990101-NONE-X-v2-00000000', { waitUntil: 'load' });
    await p2.waitForFunction(() => /Failed to load session/.test(document.getElementById('main-content').textContent));
    h.clean(p2, { bad: /api\/ltx\.php/ });
    await p2.ctx.close();
    await page.ctx.close();
  });

  await test('distance: stats equal bodyDistance and lightTravelSeconds for sampled pairs and dates', async () => {
    const page = await h.page();
    await page.goto(site.base + '/distance.html', { waitUntil: 'load' });
    for (const [a, b, date] of [['earth', 'mars', '2026-09-29'], ['venus', 'jupiter', '2031-03-15'], ['mercury', 'neptune', '2027-12-01']]) {
      await page.selectOption('#sel-a', a);
      await page.selectOption('#sel-b', b);
      await page.fill('#inp-date', date);
      await page.dispatchEvent('#inp-date', 'change');
      await page.waitForTimeout(200);
      const d = new Date(date + 'T12:00:00Z');
      const au = PT.bodyDistance(a, b, d), s = PT.lightTravelSeconds(a, b, d);
      eq(await page.locator('#stat-au').textContent(), au.toFixed(3) + ' AU', `${a}-${b} ${date} AU`);
      eq(await page.locator('#stat-km').textContent(), (au * 149597870.7 / 1e6).toFixed(2) + ' M km', `${a}-${b} km`);
      eq(await page.locator('#stat-lm').textContent(), (s / 60).toFixed(1) + ' light-min', `${a}-${b} light-min`);
    }
    h.clean(page);
    await page.ctx.close();
  });

  await test('events: every opposition is a distance minimum and every conjunction is a blocked line of sight', async () => {
    const page = await h.page();
    await page.goto(site.base + '/events.html', { waitUntil: 'load' });
    await page.waitForSelector('#events-list .event-card', { timeout: 30000 });
    const evs = await page.evaluate(() => scanEvents(Date.now(), Date.now() + 365 * 86400000, 'all'));
    eq(await page.locator('#events-list .event-card').count(), evs.length, 'one card per event');
    assert(evs.length > 0, 'events found');
    for (const e of evs) {
      const pair = await page.evaluate((id) => PAIRS.find((p) => p.id === id), e.pairId);
      const d = new Date(e.dateMs);
      if (e.type === 'opposition') {
        const dist = PT.bodyDistance(pair.keyA, pair.keyB, d);
        assert(dist <= PT.bodyDistance(pair.keyA, pair.keyB, new Date(e.dateMs - 864e5)) &&
               dist <= PT.bodyDistance(pair.keyA, pair.keyB, new Date(e.dateMs + 864e5)), `${e.label} ${d.toISOString()} is a minimum`);
      } else {
        assert(PT.checkLineOfSight(pair.keyA, pair.keyB, d).blocked, `${e.label} ${d.toISOString()} blocked`);
      }
      eq(e.distanceAU, Math.round(PT.bodyDistance(pair.keyA, pair.keyB, d) * 1000) / 1000, e.label + ' AU');
    }
    for (const b of await page.$$eval('.filter-btn', (els) => els.map((e) => e.getAttribute('data-filter')))) {
      await page.click(`.filter-btn[data-filter="${b}"]`);
      await page.waitForFunction(() => document.getElementById('loading-msg').style.display === 'none', null, { timeout: 30000 });
      const types = await page.$$eval('#events-list .event-card', (els) => els.map((e) => e.dataset.pair));
      if (b !== 'all') assert(types.every((p) => p === b), 'filter ' + b);
    }
    h.clean(page);
    await page.ctx.close();
  });

  await test('clock: ?planet=&tz= shows getPlanetTime; unknown planet falls back to Earth', async () => {
    const page = await h.page();
    for (const [planet, tz] of [['mars', 2], ['jupiter', 0], ['moon', -3]]) {
      await page.goto(`${site.base}/clock.html?planet=${planet}&tz=${tz}`, { waitUntil: 'load' });
      await page.waitForTimeout(300);
      const r = await page.evaluate(([planet, tz]) => {
        const f = () => PlanetTime.getPlanetTime(planet, new Date(), tz).timeStringFull;
        window._clockState.render();
        const a = f(); const shown = document.getElementById('time-display').textContent; const b = f();
        return { shown, ok: shown === a || shown === b, a };
      }, [planet, tz]);
      assert(r.ok, `${planet} tz ${tz}: ${r.shown} vs ${r.a}`);
    }
    await page.goto(site.base + '/clock.html?planet=pluto', { waitUntil: 'load' });
    eq(await page.evaluate(() => window._clockState.planetKey), 'earth', 'fallback');
    h.clean(page);
    await page.ctx.close();
  });

  await test('widget: ?planets= cards show getPlanetTime; light theme param', async () => {
    const page = await h.page();
    await page.goto(site.base + '/widget.html?planets=mars,saturn,bogus&theme=light', { waitUntil: 'load' });
    await page.waitForTimeout(300);
    eq(await page.$$eval('.clock-card', (els) => els.map((e) => e.dataset.planet)), ['mars', 'saturn'], 'cards');
    assert(await page.evaluate(() => document.documentElement.classList.contains('light-mode')), 'light');
    const ok = await page.evaluate(() => { renderAll(); return Array.from(document.querySelectorAll('.clock-card')).every((c) => {
      const f = () => PlanetTime.getPlanetTime(c.dataset.planet, new Date(), 0).timeStringFull;
      const a = f(); const s = c.querySelector('.time-display').textContent; return s === a || s === f();
    }); });
    assert(ok, 'times match');
    h.clean(page);
    await page.ctx.close();
  });

  await test('topics: create a topic, submit to the outbox, send from Mars and deliver', async () => {
    const page = await h.page();
    await page.goto(site.base + '/topics.html', { waitUntil: 'load' });
    await page.fill('#new-topic-title', 'Sweep topic');
    await page.click('#new-topic-form button[type=submit]');
    assert((await page.locator('#topic-list').textContent()).includes('Sweep topic'), 'topic listed');
    await page.fill('#draft', 'Hello from Earth');
    await page.click('#composer button[type=submit]');
    assert((await page.locator('#outbox').textContent()).includes('Hello from Earth'), 'in outbox');
    await page.fill('#remote-body', 'Reply from Mars');
    await page.click('#remote-form button[type=submit]');
    assert((await page.locator('#inflight').textContent()).includes('Reply from Mars'), 'in flight');
    await page.click('#deliver-all');
    await page.waitForTimeout(200);
    assert((await page.locator('#arrivals').textContent() + await page.locator('#thread').textContent()).includes('Reply from Mars'), 'delivered');
    h.clean(page);
    await page.ctx.close();
  });

  await test('playground: every snippet runs without an error', async () => {
    const page = await h.page();
    await page.goto(site.base + '/playground.html', { waitUntil: 'load' });
    const snippets = await page.$$eval('#snippet-sel option', (os) => os.map((o) => o.value));
    assert(snippets.length > 0, 'snippets');
    for (const s of snippets) {
      await page.selectOption('#snippet-sel', s);
      await page.click('#run-btn');
      await page.waitForTimeout(150);
      const out = await page.locator('#output-pre').textContent();
      assert(out.trim().length > 0 && !/^(Error|TypeError|ReferenceError)/m.test(out), `snippet ${s}: ${out.slice(0, 200)}`);
    }
    h.clean(page);
    await page.ctx.close();
  });

  await test('related-work and v1: links resolve locally and v1 shows Mars time', async () => {
    const page = await h.page();
    await page.goto(site.base + '/related-work.html', { waitUntil: 'load' });
    const local = await page.$$eval('a[href]', (as) => as.map((a) => a.getAttribute('href')).filter((u) => !/^(https?:|mailto:|#)/.test(u)));
    for (const u of local) {
      const r = await fetch(new URL(u, site.base + '/related-work.html'));
      assert(r.ok, 'local link ' + u + ' ' + r.status);
    }
    h.clean(page);
    const v1 = await h.page();
    await v1.goto(site.base + '/v1.html', { waitUntil: 'load' });
    await v1.click('text=Show Meeting Planner');
    await v1.waitForTimeout(300);
    assert((await v1.locator('#mars_row').textContent()).includes(':00'), 'mars row rendered');
    assert((await v1.locator('#mars_row_title').textContent()).startsWith('AMT'), 'mars title');
    h.clean(v1);
    await v1.ctx.close();
    await page.ctx.close();
  });
};
