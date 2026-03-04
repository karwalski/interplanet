#!/usr/bin/env node
'use strict';

/**
 * server.js — InterPlanet MCP Server
 *
 * Implements the Model Context Protocol (MCP) over stdio transport.
 * Exposes planet-time.js functions as AI tools.
 *
 * Protocol: reads newline-delimited JSON-RPC from stdin, writes to stdout.
 * Handles: initialize, tools/list, tools/call
 */

const PT = require('../../js/planet-time.js');
const readline = require('readline');

// ── Planet name → key mapping ─────────────────────────────────────────────────

const PLANET_KEYS = [
  'mercury', 'venus', 'earth', 'mars', 'jupiter',
  'saturn', 'uranus', 'neptune', 'moon'
];

function toPlanetKey(name) {
  if (!name || typeof name !== 'string') return null;
  const lower = name.toLowerCase().trim();
  if (PLANET_KEYS.includes(lower)) return lower;
  return null;
}

// ── AU → km constant ──────────────────────────────────────────────────────────
const AU_KM = 149597870.7;

// ── Tool definitions ──────────────────────────────────────────────────────────

const TOOLS = [
  {
    name: 'get_planet_time',
    description: 'Get the current local time on a planet. Returns hour, minute, second, day-of-week and work-hour status.',
    inputSchema: {
      type: 'object',
      properties: {
        planet: {
          type: 'string',
          description: 'Planet name (earth, mars, jupiter, saturn, uranus, neptune, venus, mercury, moon)'
        },
        utc_ms: {
          type: 'number',
          description: 'UTC timestamp in milliseconds (use Date.now() for current time)'
        },
        tz_offset_h: {
          type: 'number',
          description: 'Optional timezone offset in planet local hours (default 0)'
        }
      },
      required: ['planet', 'utc_ms']
    }
  },
  {
    name: 'get_light_travel',
    description: 'Calculate one-way light travel time between two bodies.',
    inputSchema: {
      type: 'object',
      properties: {
        from: {
          type: 'string',
          description: 'Origin body (planet name)'
        },
        to: {
          type: 'string',
          description: 'Destination body (planet name)'
        },
        utc_ms: {
          type: 'number',
          description: 'UTC timestamp in milliseconds'
        }
      },
      required: ['from', 'to', 'utc_ms']
    }
  },
  {
    name: 'get_mtc',
    description: 'Get Mars Time Coordinated (MTC) — the prime-meridian time on Mars.',
    inputSchema: {
      type: 'object',
      properties: {
        utc_ms: {
          type: 'number',
          description: 'UTC timestamp in milliseconds'
        }
      },
      required: ['utc_ms']
    }
  },
  {
    name: 'get_planet_distance',
    description: 'Get the distance between two solar system bodies in AU and km.',
    inputSchema: {
      type: 'object',
      properties: {
        from: {
          type: 'string',
          description: 'Origin body (planet name)'
        },
        to: {
          type: 'string',
          description: 'Destination body (planet name)'
        },
        utc_ms: {
          type: 'number',
          description: 'UTC timestamp in milliseconds'
        }
      },
      required: ['from', 'to', 'utc_ms']
    }
  },
  {
    name: 'find_meeting_windows',
    description: 'Find overlapping work-hour windows between two planets.',
    inputSchema: {
      type: 'object',
      properties: {
        planet_a: {
          type: 'string',
          description: 'First planet name'
        },
        planet_b: {
          type: 'string',
          description: 'Second planet name'
        },
        from_ms: {
          type: 'number',
          description: 'UTC start timestamp in milliseconds'
        },
        days: {
          type: 'number',
          description: 'Number of Earth days to search (default 7)'
        }
      },
      required: ['planet_a', 'planet_b', 'from_ms']
    }
  },
  {
    name: 'check_line_of_sight',
    description: 'Check whether the line of sight between two bodies is clear, degraded, or blocked by the Sun.',
    inputSchema: {
      type: 'object',
      properties: {
        from: {
          type: 'string',
          description: 'Origin body (planet name)'
        },
        to: {
          type: 'string',
          description: 'Destination body (planet name)'
        },
        utc_ms: {
          type: 'number',
          description: 'UTC timestamp in milliseconds'
        }
      },
      required: ['from', 'to', 'utc_ms']
    }
  }
];

// ── Tool handlers ─────────────────────────────────────────────────────────────

function handleGetPlanetTime(params) {
  const key = toPlanetKey(params.planet);
  if (!key) throw new Error('Unknown planet: ' + params.planet);
  if (typeof params.utc_ms !== 'number') throw new Error('utc_ms must be a number');
  const date = new Date(params.utc_ms);
  const tzOffset = typeof params.tz_offset_h === 'number' ? params.tz_offset_h : 0;
  const pt = PT.getPlanetTime(key, date, tzOffset);
  return {
    planet: pt.planet,
    symbol: pt.symbol,
    hour: pt.hour,
    minute: pt.minute,
    second: pt.second,
    time_str: pt.timeString,
    time_str_full: pt.timeStringFull,
    day_of_week: pt.dowName,
    day_of_week_short: pt.dowShort,
    is_work_hour: pt.isWorkHour,
    is_work_period: pt.isWorkPeriod,
    day_number: pt.dayNumber,
    year_number: pt.yearNumber,
    sol_info: pt.solInfo
  };
}

function handleGetLightTravel(params) {
  const keyFrom = toPlanetKey(params.from);
  const keyTo   = toPlanetKey(params.to);
  if (!keyFrom) throw new Error('Unknown origin: ' + params.from);
  if (!keyTo)   throw new Error('Unknown destination: ' + params.to);
  if (typeof params.utc_ms !== 'number') throw new Error('utc_ms must be a number');
  const date    = new Date(params.utc_ms);
  const seconds = PT.lightTravelSeconds(keyFrom, keyTo, date);
  return {
    seconds: seconds,
    formatted: PT.formatLightTime(seconds)
  };
}

function handleGetMTC(params) {
  if (typeof params.utc_ms !== 'number') throw new Error('utc_ms must be a number');
  const date = new Date(params.utc_ms);
  const mtc  = PT.getMTC(date);
  return {
    sol: mtc.sol,
    hour: mtc.hour,
    minute: mtc.minute,
    second: mtc.second,
    time_str: String(mtc.hour).padStart(2,'0') + ':' + String(mtc.minute).padStart(2,'0')
  };
}

function handleGetPlanetDistance(params) {
  const keyFrom = toPlanetKey(params.from);
  const keyTo   = toPlanetKey(params.to);
  if (!keyFrom) throw new Error('Unknown origin: ' + params.from);
  if (!keyTo)   throw new Error('Unknown destination: ' + params.to);
  if (typeof params.utc_ms !== 'number') throw new Error('utc_ms must be a number');
  const date = new Date(params.utc_ms);
  const au   = PT.bodyDistance(keyFrom, keyTo, date);
  return {
    au: au,
    km: au * AU_KM
  };
}

function handleFindMeetingWindows(params) {
  const keyA = toPlanetKey(params.planet_a);
  const keyB = toPlanetKey(params.planet_b);
  if (!keyA) throw new Error('Unknown planet_a: ' + params.planet_a);
  if (!keyB) throw new Error('Unknown planet_b: ' + params.planet_b);
  if (typeof params.from_ms !== 'number') throw new Error('from_ms must be a number');
  const days  = typeof params.days === 'number' ? params.days : 7;
  const start = new Date(params.from_ms);
  const wins  = PT.findMeetingWindows(keyA, keyB, days, start);
  return wins.map(w => ({
    start_ms: w.startMs,
    end_ms: w.endMs,
    duration_minutes: w.durationMinutes,
    start_iso: new Date(w.startMs).toISOString(),
    end_iso: new Date(w.endMs).toISOString()
  }));
}

function handleCheckLineOfSight(params) {
  const keyFrom = toPlanetKey(params.from);
  const keyTo   = toPlanetKey(params.to);
  if (!keyFrom) throw new Error('Unknown origin: ' + params.from);
  if (!keyTo)   throw new Error('Unknown destination: ' + params.to);
  if (typeof params.utc_ms !== 'number') throw new Error('utc_ms must be a number');
  const date   = new Date(params.utc_ms);
  const result = PT.checkLineOfSight(keyFrom, keyTo, date);
  return {
    clear: result.clear,
    blocked: result.blocked,
    degraded: result.degraded,
    closest_sun_au: result.closestSunAU,
    elong_deg: result.elongDeg,
    message: result.message
  };
}

// ── JSON-RPC dispatch ─────────────────────────────────────────────────────────

function sendResponse(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

function sendError(id, code, message) {
  sendResponse({
    jsonrpc: '2.0',
    id: id ?? null,
    error: { code, message }
  });
}

function handleMessage(msg) {
  let req;
  try {
    req = JSON.parse(msg);
  } catch (e) {
    sendError(null, -32700, 'Parse error');
    return;
  }

  const { id, method, params } = req;

  if (method === 'initialize') {
    sendResponse({
      jsonrpc: '2.0',
      id,
      result: {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'interplanet-mcp', version: '0.1.0' }
      }
    });
    return;
  }

  if (method === 'notifications/initialized') {
    // No response needed for notifications
    return;
  }

  if (method === 'tools/list') {
    sendResponse({
      jsonrpc: '2.0',
      id,
      result: { tools: TOOLS }
    });
    return;
  }

  if (method === 'tools/call') {
    const toolName = params && params.name;
    const toolParams = params && params.arguments || {};

    let result;
    try {
      switch (toolName) {
        case 'get_planet_time':
          result = handleGetPlanetTime(toolParams);
          break;
        case 'get_light_travel':
          result = handleGetLightTravel(toolParams);
          break;
        case 'get_mtc':
          result = handleGetMTC(toolParams);
          break;
        case 'get_planet_distance':
          result = handleGetPlanetDistance(toolParams);
          break;
        case 'find_meeting_windows':
          result = handleFindMeetingWindows(toolParams);
          break;
        case 'check_line_of_sight':
          result = handleCheckLineOfSight(toolParams);
          break;
        default:
          sendError(id, -32601, 'Unknown tool: ' + toolName);
          return;
      }
    } catch (err) {
      sendResponse({
        jsonrpc: '2.0',
        id,
        result: {
          content: [{ type: 'text', text: 'Error: ' + err.message }],
          isError: true
        }
      });
      return;
    }

    sendResponse({
      jsonrpc: '2.0',
      id,
      result: {
        content: [{ type: 'text', text: JSON.stringify(result, null, 2) }]
      }
    });
    return;
  }

  sendError(id, -32601, 'Method not found: ' + method);
}

// ── Main: read from stdin ─────────────────────────────────────────────────────

const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on('line', line => {
  const trimmed = line.trim();
  if (trimmed) handleMessage(trimmed);
});

rl.on('close', () => {
  process.exit(0);
});

process.on('uncaughtException', err => {
  process.stderr.write('Uncaught exception: ' + err.message + '\n');
  process.exit(1);
});
