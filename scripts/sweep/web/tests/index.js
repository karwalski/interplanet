'use strict';
/**
 * index.html end to end: clocks against planet-time.js, add/remove/reorder,
 * Mars time zones, time travel, meeting planner + fairness + ICS + recurring,
 * orrery, share URL (#c= and share.php), keyboard shortcuts, theme,
 * languages, widget mode, analogue clock, holidays, easter eggs.
 */
const { test, assert, eq } = require('../lib/harness');

const SKIP_SPLASH = () => {
  try {
    localStorage.setItem('tour_seen', '1');
    localStorage.setItem('skip_welcome_back', '1');
    localStorage.setItem('sky_consent', '0');
  } catch (_) {}
};
// Offline logging the app does when the (stubbed) weather / HDTN / SLM services are down.
const OFFLINE = { console: /(HDTN|Weather|SLM|LLM) API|API 503|stubbed in sweep/ };

async function openIndex(h, site, suffix, opts) {
  const page = await h.page(Object.assign({ init: SKIP_SPLASH }, opts || {}));
  await page.goto(site.base + '/' + (suffix || ''), { waitUntil: 'load' });
  await page.waitForFunction(() => window.STATE && window.PlanetTime && document.getElementById('cities-wrap'));
  // A returning visitor with no cities gets the splash again (by design): close it.
  await page.evaluate(() => { if (!document.getElementById('splash-modal').classList.contains('off')) closeSplash(); });
  return page;
}

/** Text of a card's time element, with the expected planet time before and after reading it. */
async function planetTimeCheck(page, id, planet, tz) {
  return page.evaluate(({ id, planet, tz }) => {
    // The card refreshes on a timer: accept the value from up to 3 s ago.
    const lag = PlanetTime.getPlanetTime(planet, new Date(getNow().getTime() - 3000), tz).timeString;
    const before = PlanetTime.getPlanetTime(planet, getNow(), tz).timeString;
    const shown = document.getElementById('time-' + id).textContent.trim();
    const after = PlanetTime.getPlanetTime(planet, getNow(), tz).timeString;
    return { shown, ok: shown === before || shown === after || shown === lag, before, after };
  }, { id, planet, tz });
}

async function ids(page) {
  return page.evaluate(() => STATE.cities.map((c) => c.id));
}

module.exports = async function (h, site) {
  await test('index: first visit shows the splash; Skip closes it and remembers', async () => {
    const page = await h.page();
    await page.goto(site.base + '/', { waitUntil: 'load' });
    assert(await page.locator('#splash-modal').isVisible(), 'splash visible');
    await page.click('#splash-skip');
    await page.waitForTimeout(300);
    assert(!(await page.locator('#splash-modal').isVisible()), 'splash hidden');
    eq(await page.evaluate(() => localStorage.getItem('tour_seen')), '1', 'tour_seen');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: planet cards show getPlanetTime for every planet and the Moon; Earth cards show Intl time', async () => {
    const page = await openIndex(h, site);
    const planets = await page.evaluate(() => Object.keys(PlanetTime.PLANETS).concat(Object.keys(LOCAL_PLANETS)));
    for (const p of planets) await page.evaluate((p) => addPlanet(p, 0, null, null, { silent: true }), p);
    await page.evaluate(() => {
      addEarthCity(CITY_DB.find((c) => c.city === 'Tokyo'), { silent: true });
      addEarthCity(CITY_DB.find((c) => c.city === 'New York'), { silent: true });
    });
    await page.waitForTimeout(1500);
    const cities = await page.evaluate(() => STATE.cities.map((c) => ({ id: c.id, type: c.type, planet: c.planet, tz: c.tz })));
    eq(cities.length, planets.length + 2, 'card count');
    for (const c of cities.filter((c) => c.type === 'planet')) {
      const r = await planetTimeCheck(page, c.id, c.planet, 0);
      assert(r.ok, `${c.planet}: shown ${r.shown}, expected ${r.before}`);
    }
    for (const c of cities.filter((c) => c.type === 'earth')) {
      const r = await page.evaluate(({ id, tz }) => {
        const f = (d) => new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(d);
        const before = f(getNow());
        const shown = document.getElementById('time-' + id).textContent.trim();
        const lag = f(new Date(getNow().getTime() - 3000));   // timer refresh lag
        return { shown, ok: shown === before || shown === f(getNow()) || shown === lag, before };
      }, c);
      assert(r.ok, `${c.tz}: shown ${r.shown}, expected ${r.before}`);
    }
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: Mars time zones from search (zone-name query) add a card with that zone and offset', async () => {
    const page = await openIndex(h, site);
    const zone = await page.evaluate(() => PlanetTime.MARS_ZONES.find((z) => z.offsetHours !== 0 && /[a-z]/i.test(z.name)));
    await page.keyboard.press('Control+k');
    await page.waitForSelector('#search-modal.on');
    // Search by a word of the zone name only (not "mars").
    const word = zone.name.split(/[\s(]/).find((w) => w.length > 4) || zone.name;
    await page.fill('#search-input', word);
    await page.waitForTimeout(300);
    const sel = `#search-results .sr-zone[data-zoneid="${zone.id}"]`;
    assert(await page.locator(sel).count() > 0, `zone ${zone.id} (${zone.name}) listed for query "${word}"`);
    await page.click(sel);
    await page.waitForTimeout(600);
    const c = await page.evaluate(() => STATE.cities[STATE.cities.length - 1]);
    eq([c.planet, c.zoneId, c.tzOffset], ['mars', zone.id, zone.offsetHours], 'added zone');
    const r = await planetTimeCheck(page, c.id, 'mars', zone.offsetHours);
    assert(r.ok, `Mars ${zone.id}: shown ${r.shown}, expected ${r.before}`);
    assert((await page.locator('#zone-' + c.id).textContent()).includes(zone.id), 'zone label on the card');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: add via search, remove via the card button, drag to reorder; hash follows', async () => {
    const page = await openIndex(h, site);
    for (const name of ['London', 'Tokyo', 'Sydney']) {
      await page.keyboard.press('Control+k');
      await page.waitForSelector('#search-modal.on');
      await page.fill('#search-input', name);
      await page.waitForTimeout(200);
      await page.click('#search-results .sr-item[data-idx] >> nth=0');
      await page.waitForTimeout(300);
      if (await page.locator('#search-modal.on').count()) await page.keyboard.press('Escape');
    }
    const names = () => page.evaluate(() => STATE.cities.map((c) => c.city));
    eq((await names()).sort(), ['London', 'Sydney', 'Tokyo'], 'three cities added');
    eq(await page.locator('.city-col').count(), 3, 'three cards');
    // Remove Tokyo with its button.
    const tokyoId = await page.evaluate(() => STATE.cities.find((c) => c.city === 'Tokyo').id);
    const dom = await page.evaluate(() => Array.from(document.querySelectorAll('.city-col')).map((el) => el.id));
    eq(dom.sort(), (await ids(page)).map((i) => 'city-' + i).sort(), 'one card per city');
    // Manage mode shows the remove buttons and enables drag to reorder.
    await page.click('#manage-btn');
    await page.waitForTimeout(200);
    await page.click(`#city-${tokyoId} .remove-btn`);
    await page.waitForTimeout(200);
    eq((await names()).sort(), ['London', 'Sydney'], 'Tokyo removed');
    const hashCities = await page.evaluate(() => JSON.parse(_fromBase64url(location.hash.slice(3))).cities.map((c) => c.city));
    eq(hashCities.sort(), ['London', 'Sydney'], 'hash updated');
    // Reorder: drag the second card before the first.
    const before = await names();
    const [a, b] = await ids(page);
    await page.locator('#city-' + b).dragTo(page.locator('#city-' + a), { targetPosition: { x: 5, y: 40 } });
    await page.waitForTimeout(300);
    const after = await names();
    eq(after, [before[1], before[0]], 'order swapped');
    assert(await page.evaluate(() => STATE.settings.manualOrder), 'manualOrder set');
    const domOrder = await page.evaluate(() => Array.from(document.querySelectorAll('.city-col')).map((el) => el.id));
    eq(domOrder, (await ids(page)).map((i) => 'city-' + i), 'DOM order follows STATE');
    // The share URL keeps the manual order.
    const hash = await page.evaluate(() => location.hash);
    const p2 = await openIndex(h, site, hash);
    await p2.waitForTimeout(500);
    eq(await p2.evaluate(() => STATE.cities.map((c) => c.city)), after, 'order survives the #c= link');
    h.clean(page, OFFLINE);
    h.clean(p2, OFFLINE);
    await p2.ctx.close();
    await page.ctx.close();
  });

  await test('index: time travel scrubber steps and resets; cards follow getNow()', async () => {
    const page = await openIndex(h, site);
    await page.evaluate(() => addPlanet('mars', 0, null, null, { silent: true }));
    const id = (await ids(page))[0];
    await page.click('#tt-btn');
    assert(await page.locator('#tt-bar.on').count() === 1, 'bar open');
    await page.click('#tt-fwd-day');
    await page.click('#tt-fwd-hour');
    eq(await page.evaluate(() => STATE.timeTravelMs), 25 * 3600000, 'offset +25h');
    assert((await page.locator('#tt-badge').textContent()).includes('+1d'), 'badge +1d');
    await page.waitForTimeout(1200);
    const r = await planetTimeCheck(page, id, 'mars', 0);
    assert(r.ok, `Mars at +25h: shown ${r.shown}, expected ${r.before}`);
    // Type a date into the input.
    await page.fill('#tt-input', '2030-01-01T12:00');
    await page.dispatchEvent('#tt-input', 'change');
    await page.waitForTimeout(1200);
    const target = await page.evaluate(() => getNow().toISOString().slice(0, 13));
    assert(target === '2030-01-01T12' || target === '2030-01-01T11', 'traveled to the typed time (UTC browser): ' + target);
    const r2 = await planetTimeCheck(page, id, 'mars', 0);
    assert(r2.ok, `Mars in 2030: shown ${r2.shown}, expected ${r2.before}`);
    await page.click('#tt-live-btn');
    eq(await page.evaluate(() => STATE.timeTravelMs), 0, 'live');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: meeting planner finds an overlap, fairness matches, ICS and recurring series download', async () => {
    const page = await openIndex(h, site);
    await page.evaluate(() => {
      addEarthCity(CITY_DB.find((c) => c.city === 'London'), { silent: true });
      addEarthCity(CITY_DB.find((c) => c.city === 'New York'), { silent: true });
      addPlanet('mars', 0, null, null, { silent: true });
    });
    await page.click('#meeting-btn');
    await page.waitForSelector('#meeting-panel.on');
    await page.click('#mp-overlap-btn');
    await page.waitForSelector('#mp-overlap-result .mp-fairness-badge', { timeout: 20000 });
    const badge = await page.locator('#mp-overlap-result .mp-fairness-badge').textContent();
    const expected = await page.evaluate(() => {
      const next = findNextOverlap(STATE.cities, new Date());
      const n = STATE.cities.filter((c) => c.type === 'planet'
        ? PlanetTime.getPlanetTime(c.planet, next, c.tzOffset || 0).isWorkHour
        : workStatusAt(c.tz, c.workWeek, next) === 'work').length;
      return { n, ms: next.getTime() };
    });
    assert(badge.includes(`${expected.n}/3 in work hours`), `fairness badge "${badge}" vs ${expected.n}/3`);
    const [dl] = await Promise.all([page.waitForEvent('download'), page.click('#mp-overlap-result .mp-ics-btn')]);
    const ics = await streamText(await dl.createReadStream());
    checkIcs(ics);
    const d = new Date(expected.ms);
    const stamp = d.toISOString().replace(/[-:]/g, '').slice(0, 13) + '00Z';
    assert(ics.includes('DTSTART:' + stamp), `DTSTART ${stamp} in ICS`);
    const summary = (ics.replace(/\r\n /g, '').match(/\r\nSUMMARY:(.*)\r\n/) || [])[1] || '';
    assert(['London', 'New York', 'Mars'].every((n) => summary.includes(n)) && (summary.match(/\\,/g) || []).length === 2,
      'SUMMARY names all three with escaped commas: ' + summary);
    assert(/\r\nLTX-DELAY;NODEID=MARS:ONEWAY-MIN=\d+;ONEWAY-MAX=\d+;ONEWAY-ASSUMED=\d+\r\n/.test(ics), 'integer-second LTX-DELAY for Mars');
    assert(/\r\nLTX-MODE:LTX-RELAY\r\n/.test(ics), 'spec LTX-MODE');
    // Recurring series button in the rotation preview (London + New York recur weekly).
    await page.evaluate(() => removeCity(STATE.cities.find((c) => c.type === 'planet').id));
    await page.click('#mp-overlap-btn');
    await page.waitForSelector('#mp-overlap-result .mp-series-ics-btn', { timeout: 10000 });
    const [dl2] = await Promise.all([page.waitForEvent('download'), page.click('#mp-overlap-result .mp-series-ics-btn')]);
    const series = await streamText(await dl2.createReadStream());
    checkIcs(series);
    assert((series.match(/BEGIN:VEVENT/g) || []).length >= 2, 'several VEVENTs in the series');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: orrery opens and draws; closes with its button', async () => {
    const page = await openIndex(h, site);
    await page.click('#orrery-btn');
    await page.waitForTimeout(800);
    assert(await page.locator('#orrery-panel.on').count() === 1, 'panel open');
    const painted = await page.evaluate(() => {
      const c = document.getElementById('orrery-canvas');
      const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
      let n = 0;
      for (let i = 3; i < d.length; i += 4) if (d[i] > 0) n++;
      return n;
    });
    assert(painted > 100, 'canvas has drawn pixels: ' + painted);
    await page.click('#orrery-close');
    await page.waitForTimeout(300);
    assert(await page.locator('#orrery-panel.on').count() === 0, 'panel closed');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: share URL #c= round trip (cities, Mars zone) and the share button (share.php link)', async () => {
    const page = await openIndex(h, site, '', { permissions: ['clipboard-read', 'clipboard-write'] });
    await page.evaluate(() => {
      addEarthCity(CITY_DB.find((c) => c.city === 'Paris'), { silent: true });
      const z = PlanetTime.MARS_ZONES.find((z) => z.offsetHours === 3) || PlanetTime.MARS_ZONES[1];
      addPlanet('mars', z.offsetHours, z.id, z.name, { silent: true });
      addPlanet('jupiter', 0, null, null, { silent: true });
    });
    const want = await page.evaluate(() => STATE.cities.map((c) => [c.type, c.city, c.planet || null, c.zoneId || null, c.tzOffset || 0]));
    const hash = await page.evaluate(() => location.hash);
    assert(/^#c=[A-Za-z0-9_-]+$/.test(hash), 'hash set: ' + hash);
    const p2 = await openIndex(h, site, hash);
    await p2.waitForTimeout(500);
    eq(await p2.evaluate(() => STATE.cities.map((c) => [c.type, c.city, c.planet || null, c.zoneId || null, c.tzOffset || 0])), want, 'restored from #c=');
    // Share button: stores the config via share.php and copies a ?share= link.
    await page.click('#share-ctl');
    await page.waitForTimeout(800);
    const copied = await page.evaluate(() => navigator.clipboard.readText());
    const m = copied.match(/[?&]share=([A-Za-z0-9]{6})/);
    assert(m, 'share link copied: ' + copied);
    const p3 = await h.page({ init: SKIP_SPLASH });
    await p3.goto(site.base + '/?share=' + m[1], { waitUntil: 'load' });
    await p3.waitForFunction(() => window.STATE && STATE.cities.length === 3, null, { timeout: 5000 });
    eq(await p3.evaluate(() => STATE.cities.map((c) => [c.type, c.city, c.planet || null, c.zoneId || null, c.tzOffset || 0])), want, 'restored from ?share=');
    for (const p of [page, p2, p3]) { h.clean(p, OFFLINE); await p.ctx.close(); }
  });

  await test('index: keyboard shortcuts (?, Escape, Ctrl+K, arrows between cards)', async () => {
    const page = await openIndex(h, site);
    await page.evaluate(() => { addPlanet('mars', 0, null, null, { silent: true }); addPlanet('venus', 0, null, null, { silent: true }); });
    await page.keyboard.press('?');
    assert(await page.locator('#kbd-panel.on').count() === 1, '? opens the shortcuts panel');
    await page.keyboard.press('Escape');
    assert(await page.locator('#kbd-panel.on').count() === 0, 'Escape closes it');
    await page.keyboard.press('Control+k');
    assert(await page.locator('#search-modal.on').count() === 1, 'Ctrl+K opens search');
    await page.keyboard.type('?');
    assert(await page.locator('#kbd-panel.on').count() === 0, '? typed in the search box does not open the panel');
    await page.keyboard.press('Escape');
    assert(await page.locator('#search-modal.on').count() === 0, 'Escape closes search');
    const [a, b] = await ids(page);
    await page.focus('#city-' + a);
    await page.keyboard.press('ArrowRight');
    eq(await page.evaluate(() => document.activeElement.id), 'city-' + b, 'ArrowRight moves focus');
    await page.keyboard.press('ArrowLeft');
    eq(await page.evaluate(() => document.activeElement.id), 'city-' + a, 'ArrowLeft moves back');
    await page.keyboard.press('ArrowDown');
    eq(await page.evaluate(() => document.activeElement.id), 'a11y-' + a, 'ArrowDown to details');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: theme select switches light and dark; system follows prefers-color-scheme', async () => {
    const page = await openIndex(h, site, '', { colorScheme: 'light' });
    const light = () => page.evaluate(() => document.documentElement.classList.contains('light-mode'));
    await page.evaluate(() => { STATE.settings.theme = 'system'; applyTheme('system'); });
    assert(await light(), 'system + light scheme is light');
    await page.evaluate(() => openSettings());
    await page.selectOption('#s-theme', 'dark');
    assert(!(await light()), 'dark');
    await page.selectOption('#s-theme', 'light');
    assert(await light(), 'light');
    const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    assert(bg !== 'rgba(0, 0, 0, 0)', 'body has a background');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: every supported language applies (lang/dir set, no raw keys shown)', async () => {
    const page = await openIndex(h, site);
    await page.evaluate(() => addPlanet('mars', 0, null, null, { silent: true }));
    const langs = await page.evaluate(() => I18N.SUPPORTED_LANGS);
    assert(langs.length >= 10, 'ten languages');
    await page.evaluate(() => openSettings());
    for (const lang of langs) {
      await page.selectOption('#s-lang', lang);
      await page.waitForTimeout(100);
      const r = await page.evaluate(() => {
        const raw = Array.from(document.querySelectorAll('[data-i18n]'))
          .filter((el) => el.textContent.trim() === el.getAttribute('data-i18n')).map((el) => el.getAttribute('data-i18n'));
        return { lang: document.documentElement.lang, dir: document.documentElement.dir, raw, sel: document.getElementById('s-lang').value };
      });
      eq([r.lang, r.sel], [lang, lang], 'html lang and selector');
      eq(r.dir, lang === 'ar' ? 'rtl' : 'ltr', 'dir');
      eq(r.raw, [], `raw keys in ${lang}`);
    }
    await page.selectOption('#s-lang', 'en');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: widget mode ?widget=1 (no splash, postMessage addPlanet/getState/clear)', async () => {
    const page = await h.page();
    await page.goto(site.base + '/?widget=1', { waitUntil: 'load' });
    await page.waitForFunction(() => window.STATE);
    assert(await page.evaluate(() => document.body.classList.contains('widget-mode')), 'widget-mode class');
    assert(!(await page.locator('#splash-modal').isVisible()), 'no splash');
    await page.evaluate(() => window.postMessage({ source: 'interplanet-widget', action: 'addPlanet', payload: { planet: 'mars' } }, '*'));
    await page.waitForFunction(() => STATE.cities.length === 1);
    const state = await page.evaluate(() => new Promise((res) => {
      window.addEventListener('message', (e) => { if (e.data && e.data.type === 'state') res(e.data.payload); });
      window.postMessage({ source: 'interplanet-widget', action: 'getState' }, '*');
    }));
    eq(state.cities.map((c) => c.planet), ['mars'], 'getState');
    await page.evaluate(() => window.postMessage({ source: 'interplanet-widget', action: 'clear' }, '*'));
    await page.waitForFunction(() => STATE.cities.length === 0);
    eq(await page.locator('.city-col').count(), 0, 'cleared');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: analogue clock view shows hands at the planet time', async () => {
    const page = await openIndex(h, site);
    await page.evaluate(() => addPlanet('mars', 0, null, null, { silent: true }));
    const id = (await ids(page))[0];
    await page.evaluate(() => openSettings());
    await page.click('#clock-view-seg .sp-seg-btn[data-val="analog"]');
    await page.waitForTimeout(1200);
    assert(await page.locator('#aclock-' + id).isVisible(), 'analogue clock visible');
    const r = await page.evaluate((id) => {
      const pt = PlanetTime.getPlanetTime('mars', getNow(), 0);
      const t = document.getElementById('aclock-hr-' + id).getAttribute('transform');
      const deg = Number((t || '').match(/rotate\(([-\d.]+)/)[1]);
      return { deg, want: (pt.hour % 12) * 30 + pt.minute * 0.5 };
    }, id);
    assert(Math.abs(r.deg - r.want) <= 0.5, `hour hand ${r.deg} vs ${r.want}`);
    await page.click('#clock-view-seg .sp-seg-btn[data-val="digital"]');
    await page.waitForTimeout(300);
    assert(!(await page.locator('#aclock-' + id).isVisible()), 'hidden again in digital view');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: holidays show on the day (Christmas in London via time travel)', async () => {
    const page = await openIndex(h, site);
    await page.evaluate(() => addEarthCity(CITY_DB.find((c) => c.city === 'London'), { silent: true }));
    await page.evaluate(() => timeTravelTo('2026-12-25T12:00:00Z'));
    await page.waitForTimeout(1500);
    const id = (await ids(page))[0];
    const txt = await page.locator('#holiday-' + id).textContent();
    assert(/Christmas/i.test(txt), 'holiday badge: ' + txt);
    assert(await page.locator('#holiday-' + id).isVisible(), 'badge visible');
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });

  await test('index: easter eggs (Pluto via 8 gear clicks, Konami Kerbal mode) do not throw', async () => {
    const page = await openIndex(h, site);
    for (let i = 0; i < 8; i++) await page.click('#settings-ctl');
    await page.waitForTimeout(300);
    assert(await page.evaluate(() => !!LOCAL_PLANETS.pluto), 'Pluto unlocked');
    await page.keyboard.press('Escape');
    await page.evaluate(() => addPlanet('pluto', 0, null, null, { silent: true }));
    await page.waitForTimeout(1200);
    const id = (await ids(page))[0];
    assert(/\d\d:\d\d/.test(await page.locator('#time-' + id).textContent()), 'Pluto card has a time');
    for (const k of ['ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ArrowLeft', 'ArrowRight', 'b', 'a']) {
      await page.keyboard.press(k);
    }
    await page.waitForTimeout(600);
    h.clean(page, OFFLINE);
    await page.ctx.close();
  });
};

async function streamText(stream) {
  const chunks = [];
  for await (const c of stream) chunks.push(c);
  return Buffer.concat(chunks).toString('utf8');
}

/** CRLF lines, folded at 75 octets, VCALENDAR/VEVENT balanced. */
function checkIcs(ics) {
  const lines = ics.split('\r\n');
  if (lines[lines.length - 1] === '') lines.pop();
  eq(lines[0], 'BEGIN:VCALENDAR', 'starts with BEGIN:VCALENDAR');
  eq(lines[lines.length - 1], 'END:VCALENDAR', 'ends with END:VCALENDAR');
  for (const l of lines) {
    assert(!/[\r\n]/.test(l), 'bare CR/LF inside a line');
    assert(Buffer.byteLength(l) <= 75, 'line over 75 octets: ' + l);
  }
  eq((ics.match(/BEGIN:VEVENT/g) || []).length, (ics.match(/END:VEVENT/g) || []).length, 'VEVENT balanced');
}
module.exports.checkIcs = checkIcs;
module.exports.streamText = streamText;
module.exports.SKIP_SPLASH = SKIP_SPLASH;
module.exports.OFFLINE = OFFLINE;
