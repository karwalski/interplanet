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
| DELETE | `/relay/session/{id}` | Remove a session |
| POST | `/relay/{id}/send` | Queue a frame |
| GET | `/relay/{id}/receive?node={n}` | Dequeue ready frames |

## PHP equivalents

PHP versions are in `../demo/mcp-server.php` and `../demo/relay-server.php`.
The relay server PHP version uses SQLite for state persistence.
