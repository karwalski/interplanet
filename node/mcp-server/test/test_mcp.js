'use strict';

/**
 * test_mcp.js: smoke test for the MCP server over stdio (JSON-RPC lines).
 * The server exposes planet-time tools only; it computes no LTX planIds.
 *
 * Run: node test/test_mcp.js   (from node/mcp-server)
 */

const path = require('path');
const assert = require('assert');
const { spawn } = require('child_process');

const requests = [
  { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} },
  { jsonrpc: '2.0', id: 2, method: 'tools/list' },
  { jsonrpc: '2.0', id: 3, method: 'tools/call',
    params: { name: 'get_planet_time', arguments: { planet: 'mars', utc_ms: 1780000000000 } } },
];

const child = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], { stdio: ['pipe', 'pipe', 'inherit'] });
let out = '';
child.stdout.on('data', d => { out += d; });
child.on('close', () => {
  const byId = {};
  for (const line of out.split('\n').filter(Boolean)) {
    const msg = JSON.parse(line);
    byId[msg.id] = msg;
  }
  let failed = 0;
  const check = (name, fn) => {
    try { fn(); console.log('PASS ' + name); }
    catch (e) { failed++; console.log('FAIL ' + name + ': ' + e.message); }
  };
  check('initialize', () => assert.strictEqual(byId[1].result.serverInfo.name, 'interplanet-mcp'));
  check('tools/list', () => assert.ok(byId[2].result.tools.some(t => t.name === 'get_planet_time')));
  check('tools/call get_planet_time', () => {
    const data = JSON.parse(byId[3].result.content[0].text);
    assert.strictEqual(data.planet, 'Mars');
  });
  console.log(failed ? `\n${failed} failed` : '\nall passed');
  process.exit(failed ? 1 : 0);
});
child.stdin.end(requests.map(r => JSON.stringify(r)).join('\n') + '\n');
