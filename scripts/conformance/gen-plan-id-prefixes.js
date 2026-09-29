#!/usr/bin/env node
/**
 * gen-plan-id-prefixes.js: regenerate spec/golden/plan-id-prefixes.json
 * (issue #37) from the JavaScript reference SDK (javascript/ltx/ltx-sdk.js).
 *
 * The vectors exercise the HOSTSTR / NODESTR prefix of the planId
 * (docs/LTX-SPECIFICATION.md section 4.3): JS whitespace removal (/\s/g),
 * locale-independent full Unicode upper-casing (String.prototype.toUpperCase,
 * including one-to-many special casing such as ß to SS) and slicing to 8, 4
 * and 16 UTF-16 code units, which can leave a lone high surrogate.
 *
 * Usage:  node scripts/conformance/gen-plan-id-prefixes.js [--check]
 *   --check  compare with the committed file instead of writing it
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'spec/golden/plan-id-prefixes.json');
const LTX = require(path.join(ROOT, 'javascript/ltx/ltx-sdk.js'));
const pkg = require(path.join(ROOT, 'javascript/ltx/package.json'));

const LOCATIONS = ['earth', 'mars', 'moon', 'jupiter', 'mars'];

function nodesOf(names) {
  return names.map((name, i) => ({
    id: `N${i}`,
    name,
    role: i === 0 ? 'HOST' : 'PARTICIPANT',
    delay: i === 0 ? 0 : 120 * i,
    location: LOCATIONS[i % LOCATIONS.length],
  }));
}

// Plans are built with createPlan (segments before nodes, as JS) unless
// nodesFirst is set, in which case the keys are in the order most typed
// ports serialise (v, title, start, quantum, mode, nodes, segments).
function plan(names, opts) {
  opts = opts || {};
  const p = LTX.createPlan({
    title: opts.title || 'Prefix ' + names[0],
    start: opts.start || '2026-10-01T12:00:00.000Z',
    quantum: 5,
    mode: 'LTX',
    nodes: nodesOf(names),
  });
  if (!opts.nodesFirst) return p;
  const { v, title, start, quantum, mode, nodes, segments } = p;
  return { v, title, start, quantum, mode, nodes, segments };
}

const CASES = [
  ['latin-accents', 'Latin-1 accents; a decomposed é (e + U+0301) stays two code units (no normalisation).',
    plan(['Équipe Été', 'café münchen', 'Ñandú', 'Café X'])],
  ['sharp-s-expansion', 'ß upper-cases to SS before slicing: HOSTSTR is 8 units of the expanded string.',
    plan(['Straße 12', 'ßa', 'Groß', 'ẞig'], { nodesFirst: true })],
  ['ligatures', 'Latin ligatures ﬁ ﬂ ﬀ ﬃ ﬆ and ŉ (to ʼN) expand before slicing.',
    plan(['ﬁeld ﬂow', 'ﬀﬁ', 'ŉa', 'ﬃx', 'ﬆop'])],
  ['cut-inside-expansion', 'The 8-unit and 4-unit cuts fall inside a special-casing expansion (ŉ to ʼN, ΐ to Ϊ́, ﬃ to FFI).',
    plan(['abcdefgŉ', 'abΐ', 'aaﬃ'])],
  ['greek-sigma', 'Greek: σ and final ς both map to Σ, tonos vowels, µ (U+00B5) to Μ, ᾳ to ΑΙ, ᾈ to ἈΙ.',
    plan(['σοφίας', 'ΐλη', 'ᾳδης', 'ς', 'µᾈ'], { nodesFirst: true })],
  ['cyrillic', 'Cyrillic, including ё, ї and historic ѣ.',
    plan(['Москва Юг', 'ёлка', 'Київ', 'ѣра'])],
  ['turkish-dotless', 'Locale-independent Turkish: ı to I, i to I (not İ), İ unchanged.',
    plan(['ıstanbul', 'iğdır', 'İzmir'])],
  ['armenian-ligature', 'Armenian: և to ԵՒ, ﬓ to ՄՆ, ﬔ to ՄԵ.',
    plan(['Երևան', 'ﬓﬔ', 'և'], { nodesFirst: true })],
  ['cjk-unicode-space', 'CJK and Hangul are uncased; U+3000, U+00A0 and U+2009 are JS whitespace and are removed.',
    plan(['東京　宇宙 センター', '北京 站', '서울 기지', 'a b c'])],
  ['js-whitespace-set', 'Exactly the JS \\s set is removed: U+FEFF, U+1680, U+2000..U+200A, U+2028, U+202F, U+205F, tab, VT and FF are; U+0085 (NEL), U+001C..U+001F, U+180E and U+200B are not.',
    plan(['a﻿b c d e', 'x\u0085y', 'p\u001cq\u001fr', 'm᠎n​o', 't\tu\u000bv\u000cw  z'])],
  ['emoji-split-host', 'HOSTSTR cut at 8 units splits 🚀 (U+1F680): the id keeps the lone high surrogate U+D83D.',
    plan(['Rockets🚀', 'Mars', 'abc🚀', '🚀🚀'])],
  ['emoji-split-node', 'NODESTR cut at 4 units splits an emoji; a whole emoji fits exactly.',
    plan(['Hub', 'x🛰x', 'abc🌍', '🌍a'], { nodesFirst: true })],
  ['emoji-split-after-sharp-s', 'Only after ß expands to SS does the 8-unit cut split 🌍 (a simple upper-case mapping would not split it); ﬃ likewise at 4 units.',
    plan(['Straße🌍', 'ß🌍', 'ﬃ🌍'])],
  ['nodestr-16-split', 'The 16-unit NODESTR cut splits the emoji that starts the fourth token.',
    plan(['Hub', 'Mars', 'Luna', 'Titan', '🚀ab'])],
  ['astral-cased', 'Astral cased letters (Deseret U+10428.. to U+10400..) are surrogate pairs; the 4-unit cut splits the second one.',
    plan(['𐐨𐐯𐐹ab', '𐐨𐐩𐐪', 'a𐐨𐐩'])],
  ['latin-extended-single', 'Single-node plan (NODESTR "RX"): ǆ to Ǆ, ÿ to Ÿ, ſ to S, ǰ to J̌.',
    plan(['ǆÿſǰ nx'])],
  ['latin-titlecase-digraph', 'Titlecase digraph ǅ to Ǆ, ǈ to Ǉ; Latin Extended Additional ạ to Ạ.',
    plan(['ǅǈạ', 'ǋạ', 'ǲ'], { nodesFirst: true })],
];

function utf8Form(s) {
  // What JS writes when the id is encoded to UTF-8 (TextEncoder, Buffer,
  // HTTP): each lone surrogate becomes U+FFFD.
  return Buffer.from(s, 'utf8').toString('utf8');
}

function wtf8Hex(s) {
  // WTF-8 (generalized UTF-8): code points as UTF-8, and each lone surrogate
  // as the 3-byte sequence ED A0..BF xx, the form in which the ports with
  // byte strings (C, Ruby, PHP, Julia, OCaml, Lua, ...) hold one.
  const bytes = [];
  for (let i = 0; i < s.length; i++) {
    let cp = s.charCodeAt(i);
    if (cp >= 0xD800 && cp < 0xDC00 && i + 1 < s.length) {
      const lo = s.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo < 0xE000) { cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00); i++; }
    }
    if (cp < 0x80) bytes.push(cp);
    else if (cp < 0x800) bytes.push(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F));
    else if (cp < 0x10000) bytes.push(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
    else bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
  }
  return Buffer.from(bytes).toString('hex');
}

const vectors = [];
function add(name, description, p) {
  const planId = LTX.makePlanId(p);
  const planIdUtf8 = utf8Form(planId);
  vectors.push({
    name, description, plan: p, planId, planIdUtf8, planIdWtf8Hex: wtf8Hex(planId),
    loneSurrogate: planId !== planIdUtf8,
  });
}
for (const [name, description, p] of CASES) add(name, description, p);
// v3: the prefix is the same; the digest is SHA-256 over canonical JSON.
add('v3-greek-emoji', 'v3 (upgradePlanToV3) plan with cased Greek and a split emoji in NODESTR.',
  LTX.upgradePlanToV3(plan(['Ωmega σ', 'abc🚀', 'ßeta']), { delays: { 'N1|N2': 300 } }));
add('v3-sharp-s-split', 'v3 plan whose HOSTSTR splits 🌍 only after ß expands.',
  LTX.upgradePlanToV3(plan(['Straße🌍', 'ﬁx'])));

const doc = {
  description:
    'LTX planId prefix golden vectors (issue #37, docs/LTX-SPECIFICATION.md section 4.3). ' +
    'HOSTSTR is the HOST name with JS whitespace (/\\s/) removed, upper-cased with the locale-independent ' +
    'full Unicode mapping of String.prototype.toUpperCase (special casing included: ß to SS, ﬁ to FI, ŉ to ʼN, ΐ to Ϊ́, ᾳ to ΑΙ), ' +
    'then sliced to 8 UTF-16 code units; NODESTR is each other node name treated the same way and sliced to 4 units, ' +
    'joined with "-" and sliced to 16 units ("RX" for a single-node plan). Slicing can split a surrogate pair and leave a ' +
    'lone high surrogate in the id. planId is the exact JS string (a lone surrogate appears as a \\ud83d escape). ' +
    'planIdWtf8Hex is the hex of its WTF-8 bytes (a lone surrogate as ED A0..BF xx). ' +
    'planIdUtf8 is the same id as JS encodes it to UTF-8 (TextEncoder, Buffer, HTTP): each lone surrogate becomes U+FFFD. ' +
    'A port keeps the lone surrogate where its string type can hold it: ports whose strings are UTF-16 or code points ' +
    '(JS, TypeScript, Python, Dart, Java, Kotlin, C#, F#, Scala) MUST return planId; ports with byte strings that hold ' +
    'a lone surrogate as WTF-8 (C, Ruby, PHP, Julia, OCaml, Lua, Zig) MUST return the planIdWtf8Hex bytes; ports whose ' +
    'strings must be valid UTF-8 (Rust, Swift, Go, Elixir, R) MUST return planIdUtf8. loneSurrogate says whether the forms differ. ' +
    'The prefix (LTX-date-HOSTSTR-NODESTR) is the id without its last 12 characters ("-v2-" or "-v3-" and 8 hex digits). ' +
    'Plans are parsed preserving key order (see plan-ids.json); some vectors are in createPlan order (segments first), some nodes first. ' +
    'Regenerate with node scripts/conformance/gen-plan-id-prefixes.js.',
  generatedBy: `interplanet-ltx ${pkg.version} (node ${process.versions.node}, Unicode ${process.versions.unicode})`,
  vectors,
};
const text = JSON.stringify(doc, null, 2) + '\n';
if (process.argv.includes('--check')) {
  const old = fs.readFileSync(OUT, 'utf8');
  const strip = t => t.replace(/"generatedBy": "[^"]*"/, '');
  if (strip(old) !== strip(text)) { console.error('plan-id-prefixes.json is out of date'); process.exit(1); }
  console.log(`plan-id-prefixes.json up to date (${vectors.length} vectors)`);
} else {
  fs.writeFileSync(OUT, text);
  console.log(`wrote ${path.relative(ROOT, OUT)} (${vectors.length} vectors)`);
}
