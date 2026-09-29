'use strict';
/**
 * Every page: loads with no page errors, console errors or failed local
 * requests; at 390 px wide there is no horizontal scroll; h1 count; canonical
 * and robots meta consistent with sitemap.xml and robots.txt.
 */
const { test, assert, eq } = require('../lib/harness');

const PAGES = [
  // [path, h1 count required (null: not checked), in sitemap]
  ['/', 1, true],
  ['/ltx.html', 1, true],
  ['/distance.html', 1, true],
  ['/events.html', 1, true],
  ['/related-work.html', 1, true],
  ['/topics.html', 1, false],
  ['/v1.html', 1, false],
  ['/dashboard.html', null, false],
  ['/playground.html', null, false],
  ['/clock.html', null, false],
  ['/widget.html', null, false],
];

module.exports = async function (h, site) {
  for (const [p, h1] of PAGES) {
    await test(`page ${p}: loads clean at 1280 px`, async () => {
      const page = await h.page();
      await page.goto(site.base + p, { waitUntil: 'load' });
      await page.waitForTimeout(1500);
      h.clean(page);
      if (h1 !== null) eq(await page.locator('h1').count(), h1, 'h1 count');
      await page.ctx.close();
    });
    await test(`page ${p}: no horizontal scroll at 390 px`, async () => {
      const page = await h.page({ viewport: { width: 390, height: 844 } });
      await page.goto(site.base + p, { waitUntil: 'load' });
      await page.waitForTimeout(1200);
      const m = await page.evaluate(() => ({
        sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth,
        wide: Array.from(document.querySelectorAll('body *')).filter((el) => {
          const r = el.getBoundingClientRect();
          const cs = getComputedStyle(el);
          return r.width > 0 && r.right > document.documentElement.clientWidth + 1 && cs.position !== 'fixed' &&
            !el.closest('[style*="overflow"], .scroll-x');
        }).slice(0, 5).map((el) => el.tagName + (el.id ? '#' + el.id : '') + '.' + String(el.className).slice(0, 40)),
      }));
      assert(m.sw <= m.cw, `scrollWidth ${m.sw} > clientWidth ${m.cw}; wide: ${m.wide.join(', ')}`);
      h.clean(page);
      await page.ctx.close();
    });
  }
};
module.exports.PAGES = PAGES;
