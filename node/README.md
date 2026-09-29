# InterPlanet — Node.js Servers

Node.js implementations of the InterPlanet MCP and relay servers.

## mcp-server

MCP (Model Context Protocol) server exposing planet-time functions as AI tools.

```bash
cd mcp-server
node server.js          # stdio transport (for Claude Desktop / MCP clients)
```

## relay-server

LTX DTN store-and-forward relay server for interplanetary meetings.

```bash
cd relay-server
node server.js          # listens on port 3000
node server.js --port 8080
PORT=8080 node server.js
```

### Relay API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/relay/health` | Server status |
| POST | `/relay/session` | Register a session |
| DELETE | `/relay/session/{id}` | Remove a session (needs `Authorization: Bearer <tls_fingerprint>`) |
| POST | `/relay/{id}/send` | Queue a frame |
| GET | `/relay/{id}/receive?node={n}` | Dequeue ready frames |

`POST /relay/session` returns the session's `tls_fingerprint`, the bearer
token that `send`, `receive` and `DELETE` require. Registering a plan whose
session is already live returns 409 unless the request carries that token
(as a bearer token, or as the plan's `relay.tls_fingerprint`); the owner
re-registering keeps its token. The PHP relay (`demo/relay-server.php`)
behaves the same.

The session `{id}` (`sessionId`, also returned as `planId`) is the spec planId
of the registered plan (docs/LTX-SPECIFICATION.md sections 4.3 and 4.5), the
same value `makePlanId()` gives in every SDK. It can contain non-ASCII node
names, so percent-encode it in URLs.

`npm test` in `relay-server/` checks it against `spec/golden/plan-ids.json`;
`php api/tests/test_planid.php` (repository root) does the same for
`api/ltx.php` and `demo/relay-server.php`.

## PHP equivalents

PHP versions are in `../demo/mcp-server.php` and `../demo/relay-server.php`.
The relay server PHP version uses SQLite for state persistence.
