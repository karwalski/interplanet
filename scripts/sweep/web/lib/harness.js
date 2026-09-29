'use strict';
/**
 * Playwright harness for the sweep web suite.
 *
 * Every request that leaves the local site is intercepted and answered with
 * a stub (CDNs and third-party APIs are blocked in CI sandboxes and must not
 * make results flaky): stylesheets get empty CSS, scripts an empty script,
 * JSON-looking API calls a 503 JSON error (so the page's offline paths run),
 * anything else an empty 204. Each page records uncaught page errors,
 * console errors, failed local requests and local responses >= 400.
 */
const path = require('path');

let chromium;
try { ({ chromium } = require('playwright')); }
catch (_) { ({ chromium } = require(path.join('/opt/node22/lib/node_modules', 'playwright'))); }

const results = { passed: 0, failed: 0, failures: [] };
let only = null;
function setFilter(re) { only = re; }

async function test(name, fn) {
  if (only && !only.test(name)) return;
  const t0 = Date.now();
  try {
    await fn();
    results.passed++;
    console.log(`PASS ${name} (${Date.now() - t0} ms)`);
  } catch (e) {
    results.failed++;
    results.failures.push(name);
    console.log(`FAIL ${name}: ${(e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e)}`);
  }
}

function stubFor(route) {
  const req = route.request();
  const type = req.resourceType();
  const url = req.url();
  if (type === 'stylesheet' || /\.css(\?|$)/.test(url)) return { status: 200, contentType: 'text/css', body: '' };
  if (type === 'script' || /\.m?js(\?|$)/.test(url)) return { status: 200, contentType: 'application/javascript', body: '' };
  if (type === 'font') return { status: 404, body: '' };
  if (type === 'image') return { status: 404, body: '' };
  if (type === 'document') return { status: 200, contentType: 'text/html', body: '<!doctype html><title>stub</title>' };
  return { status: 503, contentType: 'application/json', body: '{"error":"stubbed in sweep"}' };
}

class Harness {
  constructor(base) { this.base = base; this.browser = null; this.external = new Set(); }

  async start() {
    this.browser = await chromium.launch({ args: ['--no-sandbox'] });
  }

  async stop() { if (this.browser) await this.browser.close(); }

  /**
   * New context + page. opts: viewport, colorScheme, locale, serviceWorkers,
   * init (script run before page scripts), stub (fn(route) -> fulfill opts or null).
   */
  async page(opts) {
    const o = opts || {};
    const ctx = await this.browser.newContext({
      viewport: o.viewport || { width: 1280, height: 900 },
      colorScheme: o.colorScheme || 'dark',
      locale: o.locale || 'en-US',
      timezoneId: o.timezoneId || 'UTC',
      serviceWorkers: o.serviceWorkers || 'block',
      acceptDownloads: true,
      permissions: o.permissions || [],
    });
    const origin = new URL(this.base).origin;
    await ctx.route('**/*', (route) => {
      const u = route.request().url();
      if (u.startsWith(origin) || u.startsWith('data:') || u.startsWith('blob:')) return route.fallback();
      this.external.add(new URL(u).host);
      const custom = o.stub && o.stub(route);
      return route.fulfill(custom || stubFor(route));
    });
    if (o.init) await ctx.addInitScript(o.init);
    const page = await ctx.newPage();
    const log = { pageErrors: [], consoleErrors: [], failed: [], bad: [] };
    page.on('pageerror', (e) => log.pageErrors.push(String(e && e.stack || e).split('\n').slice(0, 2).join(' ')));
    page.on('console', (m) => {
      if (m.type() !== 'error') return;
      const text = m.text();
      // Messages caused by the sweep's own stubs, not by the page.
      if (/Failed to load resource/.test(text)) return;
      if (/integrity' attribute for resource 'https?:\/\/(?!127\.0\.0\.1)/.test(text)) return;   // SRI on a stub
      log.consoleErrors.push(text);
    });
    page.on('requestfailed', (r) => {
      if (r.url().startsWith(origin)) log.failed.push(`${r.url()} ${r.failure() && r.failure().errorText}`);
    });
    page.on('response', (r) => {
      if (r.url().startsWith(origin) && r.status() >= 400) log.bad.push(`${r.status()} ${r.url()}`);
    });
    page.log = log;
    page.ctx = ctx;
    return page;
  }

  /** Assert a page produced no page errors, console errors or failed/4xx local requests. */
  clean(page, allow) {
    const a = allow || {};
    const filt = (arr, re) => (re ? arr.filter((x) => !re.test(x)) : arr);
    const problems = [].concat(
      filt(page.log.pageErrors, a.pageErrors).map((x) => 'pageerror: ' + x),
      filt(page.log.consoleErrors, a.console).map((x) => 'console: ' + x),
      filt(page.log.failed, a.failed).map((x) => 'requestfailed: ' + x),
      filt(page.log.bad, a.bad).map((x) => 'http: ' + x),
    );
    if (problems.length) throw new Error(problems.join(' || '));
  }
}

function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function eq(a, b, msg) {
  const sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) throw new Error(`${msg || 'not equal'}: ${sa} !== ${sb}`);
}

module.exports = { Harness, test, results, setFilter, assert, eq };
