#!/usr/bin/env node
/**
 * check-versions.js: verify that versions.json, the port manifests and the
 * version tables in LANGUAGE-SUPPORT.md and README.md agree.
 *
 * The manifests are authoritative. versions.json records what each manifest
 * says, and the documentation tables must match versions.json.
 *
 * Usage:  node scripts/check-versions.js
 * Exit code: 0 when everything matches, 1 on any mismatch.
 * No dependencies beyond Node.js (>= 14).
 */

'use strict';

const fs   = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LIBS = ['planet-time', 'ltx'];

const errors = [];
const fail = msg => errors.push(msg);

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8');
}

function firstMatch(text, re) {
  const m = text.match(re);
  return m ? m[1].trim() : undefined;
}

/** Extract the version a file declares, from its name or an explicit pattern. */
function extractVersion(rel, pattern) {
  const text = read(rel);
  if (pattern) return firstMatch(text, new RegExp(pattern, 'm'));

  const base = path.basename(rel);
  if (base === 'package.json' || base === 'composer.json') return JSON.parse(text).version;
  if (base === 'pyproject.toml' || base === 'Cargo.toml' || base === 'Project.toml') {
    return firstMatch(text, /^version\s*=\s*"([^"]+)"/m);
  }
  if (base === 'pubspec.yaml')       return firstMatch(text, /^version:\s*(\S+)/m);
  if (base === 'mix.exs')            return firstMatch(text, /version:\s*"([^"]+)"/);
  if (base === 'DESCRIPTION')        return firstMatch(text, /^Version:\s*(\S+)/m);
  if (base === 'build.gradle.kts')   return firstMatch(text, /^version\s*=\s*"([^"]+)"/m);
  if (base === 'build.sbt')          return firstMatch(text, /^version\s*:=\s*"([^"]+)"/m);
  if (base === 'CMakeLists.txt')     return firstMatch(text, /project\([^)]*VERSION\s+([0-9][0-9.]*)/);
  if (base.endsWith('.gemspec'))     return firstMatch(text, /\.version\s*=\s*['"]([^'"]+)['"]/);
  if (/\.(cs|fs)proj$/.test(base))   return firstMatch(text, /<Version>([^<]+)<\/Version>/);
  throw new Error(`no version rule for ${rel}; add a "pattern" to versions.json`);
}

/** How a version is shown in the documentation tables. */
function display(version) {
  return version === null ? 'unversioned' : version;
}

/** Split a Markdown table row into trimmed cells. */
function cells(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
}

// ── 1. Manifests match versions.json ─────────────────────────────────────────

const manifest = JSON.parse(read('versions.json'));
let checked = 0;

for (const port of manifest.ports) {
  for (const lib of LIBS) {
    const entry = port[lib];
    if (!entry) { fail(`versions.json: ${port.language} has no "${lib}" entry`); continue; }
    if (entry.file === null) {
      if (entry.version !== null) fail(`versions.json: ${port.language} ${lib} has a version but no file`);
      continue;
    }
    let actual;
    try {
      actual = extractVersion(entry.file, entry.pattern);
    } catch (e) {
      fail(`${entry.file}: ${e.message}`);
      continue;
    }
    checked++;
    if (actual === undefined) fail(`${entry.file}: no version found`);
    else if (actual !== entry.version) {
      fail(`${port.language} ${lib}: ${entry.file} says ${actual}, versions.json says ${entry.version}`);
    }
  }
}

for (const tool of manifest.tools || []) {
  const actual = extractVersion(tool.file, tool.pattern);
  checked++;
  if (actual !== tool.version) fail(`${tool.name}: ${tool.file} says ${actual}, versions.json says ${tool.version}`);
}

const byLanguage = new Map(manifest.ports.map(p => [p.language, p]));

// ── 2. LANGUAGE-SUPPORT.md support matrix ────────────────────────────────────
// Rows look like: | **Python** | ✓ 0.1.0 | ✓ 1.1.0 | ...

const seen = new Set();
for (const line of read('LANGUAGE-SUPPORT.md').split('\n')) {
  const m = line.match(/^\|\s*\*\*([^*]+)\*\*\s*\|/);
  if (!m) continue;
  const language = m[1];
  const port = byLanguage.get(language);
  if (!port) { fail(`LANGUAGE-SUPPORT.md: "${language}" is not in versions.json`); continue; }
  seen.add(language);
  const [, pt, ltx] = cells(line);
  const want = { 'planet-time': `✓ ${display(port['planet-time'].version)}`, ltx: `✓ ${display(port.ltx.version)}` };
  if (pt !== want['planet-time']) fail(`LANGUAGE-SUPPORT.md: ${language} planet-time is "${pt}", expected "${want['planet-time']}"`);
  if (ltx !== want.ltx)           fail(`LANGUAGE-SUPPORT.md: ${language} LTX is "${ltx}", expected "${want.ltx}"`);
}
for (const language of byLanguage.keys()) {
  if (!seen.has(language)) fail(`LANGUAGE-SUPPORT.md: no support-matrix row for ${language}`);
}

// ── 3. README.md "All LTX SDK ports" table ───────────────────────────────────
// Rows look like: | Python | `interplanet-ltx` | `python/ltx/` | ✅ 1.1.0 |

const readme = read('README.md');
const start = readme.indexOf('### All LTX SDK ports');
if (start < 0) {
  fail('README.md: "### All LTX SDK ports" section not found');
} else {
  const section = readme.slice(start).split('\n').slice(1);
  let rows = 0;
  for (const line of section) {
    if (/^#{1,3} /.test(line)) break;
    if (!line.startsWith('|')) continue;
    const c = cells(line);
    const port = byLanguage.get(c[0]);
    if (!port) continue;             // header, separator, CLI row
    rows++;
    const want = `✅ ${display(port.ltx.version)}`;
    if (c[3] !== want) fail(`README.md LTX table: ${c[0]} is "${c[3]}", expected "${want}"`);
  }
  if (rows === 0) fail('README.md: no rows found in the LTX SDK table');
}

// ── Result ───────────────────────────────────────────────────────────────────

if (errors.length) {
  console.error(`Version check FAILED (${errors.length} problem${errors.length === 1 ? '' : 's'}):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
console.log(`Version check passed: ${checked} manifest versions match versions.json, ` +
            `and the LANGUAGE-SUPPORT.md and README.md tables match.`);
