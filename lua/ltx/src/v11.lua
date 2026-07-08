-- v11.lua -- LTX v1.1 core subset (Epic 72 cascade)
--
-- pair_delay / compute_segments_for (LTX-SPECIFICATION.md §3.7 / §14.3),
-- session state machine (§5), amendment-chain verify (§6.4),
-- question/action registers (§9/§10), deterministic CBOR (RFC 8949) +
-- COSE_Sign1 verify (RFC 9052).
--
-- Signature verification uses real Ed25519 (src/ed25519.lua). Signing is not
-- provided in the Lua port (pure-Lua signing would need SHA-512-based key
-- expansion of locally held seeds; the conformance requirement is the verify
-- path -- LTX-SECURITY.md §7).

local security = require("src.security")
local ed25519 = require("src.ed25519")
local ltx = require("src.interplanet_ltx")
local constants = require("src.constants")

local M = {}

M.SESSION_STATES = {
  "DRAFT", "LOCKING", "LOCKED", "ACTIVE", "DEGRADED",
  "EMERGENCY_HOLD", "COMPLETE", "ABORTED",
}

-- ── Shared helpers ───────────────────────────────────────────────────────────

local canonical_json = security.canonical_json
local b64u_encode = security.b64u_encode
local b64u_decode = security.b64u_decode

local function shallow_copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function list_copy(t)
  local out = {}
  for i, v in ipairs(t or {}) do out[i] = v end
  return out
end

-- Raw 32-byte public key from a NIK table. Accepts the cross-port raw
-- base64url form (`public_key_b64` / `publicKey`, 32 bytes) or the Lua
-- generate_nik SPKI-DER form (44 bytes; the raw key is the last 32).
local function nik_raw_pub(nik)
  local b64 = nik.public_key_b64 or nik.publicKey
  if type(b64) ~= "string" then return nil end
  local raw = b64u_decode(b64)
  if #raw == 32 then return raw end
  if #raw > 32 then return raw:sub(-32) end
  return nil
end

local function nik_expired(nik)
  local exp = nik.expires_at or nik.validUntil or nik.valid_until
  if not exp then return true end
  return exp <= os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- kid lookup: exact key match, else a NIK whose node_id starts with the kid.
local function lookup_nik(kid, key_cache)
  key_cache = key_cache or {}
  if key_cache[kid] then return key_cache[kid] end
  for _, nik in pairs(key_cache) do
    local nid = nik.node_id or nik.nodeId
    if type(nid) == "string" and nid:sub(1, #kid) == kid then return nik end
  end
  return nil
end

-- Verify a raw Ed25519 signature (base64url) against a NIK.
local function verify_bytes(message, sig_b64, nik)
  local pub = nik_raw_pub(nik)
  if not pub then return false end
  local sig = b64u_decode(sig_b64 or "")
  if #sig ~= 64 then return false end
  return ed25519.verify(message, sig, pub)
end

-- ═════════════════════════════════════════════════════════════════════════
-- 1. pair_delay + compute_segments_for (§3.7 / §14.3)
-- ═════════════════════════════════════════════════════════════════════════

--- One-way delay in seconds between two nodes (§3.7). The v3 pair matrix
-- (`delays`, key "A|B" with ids sorted) is authoritative where present;
-- otherwise the conservative fallback: HOST pairs use the node's declared
-- delay, non-HOST pairs the sum of both HOST-relative delays.
-- @return number|nil, string|nil  delay seconds, or nil + error
function M.pair_delay(plan, node_id_a, node_id_b)
  if node_id_a == node_id_b then return 0 end
  local pair = { node_id_a, node_id_b }
  table.sort(pair)
  local key = pair[1] .. "|" .. pair[2]
  if type(plan.delays) == "table" and type(plan.delays[key]) == "number" then
    return plan.delays[key]
  end
  local a, b
  for _, n in ipairs(plan.nodes or {}) do
    if n.id == node_id_a then a = n end
    if n.id == node_id_b then b = n end
  end
  if not a or not b then
    return nil, "pair_delay: unknown node " .. (a and node_id_b or node_id_a)
  end
  local host_id = plan.nodes[1].id
  if node_id_a == host_id then return b.delay or 0 end
  if node_id_b == host_id then return a.delay or 0 end
  return (a.delay or 0) + (b.delay or 0)
end

--- Compute the timed segment array from viewer V's perspective (§14.3):
-- a segment attributed to speaker S starts for V at
-- segStart + pair_delay(S, V). Unattributed segments keep their times.
-- Each result row: { type, q, start_iso, end_iso, dur_min, speaker?, label?,
--                    perspective = "transmit"|"receive"|"neutral",
--                    arrival_offset_s }
-- @return table|nil, string|nil
function M.compute_segments_for(plan, viewer_node_id)
  local known = false
  for _, n in ipairs(plan.nodes or {}) do
    if n.id == viewer_node_id then known = true end
  end
  if not known then
    return nil, "compute_segments_for: unknown viewer " .. tostring(viewer_node_id)
  end
  local base, err = ltx.compute_segments(plan)
  if not base then return nil, err end
  local out = {}
  for i, seg in ipairs(base) do
    local tpl = plan.segments[i]
    local speaker = tpl.speaker
    local row = {
      type = seg.type,
      q = seg.q,
      start_iso = seg.start_iso,
      end_iso = seg.end_iso,
      dur_min = seg.dur_min,
      speaker = speaker,
      label = tpl.label,
      perspective = "neutral",
      arrival_offset_s = 0,
    }
    if speaker and (tpl.type == "TX" or tpl.type == "SPEAK") then
      if speaker == viewer_node_id then
        row.perspective = "transmit"
      else
        local shift = M.pair_delay(plan, speaker, viewer_node_id) or 0
        row.perspective = "receive"
        row.arrival_offset_s = shift
        -- Shift the ISO times by the light-time offset.
        local function shift_iso(iso)
          local y, mo, d, h, mi, s =
            iso:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
          local now = os.time()
          local utc_offset = os.time(os.date("!*t", now)) - now
          local t = os.time({
            year = tonumber(y), month = tonumber(mo), day = tonumber(d),
            hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
            isdst = false,
          }) - utc_offset
          return os.date("!%Y-%m-%dT%H:%M:%SZ", t + shift)
        end
        row.start_iso = shift_iso(seg.start_iso)
        row.end_iso = shift_iso(seg.end_iso)
      end
    end
    out[#out + 1] = row
  end
  return out
end

-- ═════════════════════════════════════════════════════════════════════════
-- 2. transition() session state machine (§5)
-- ═════════════════════════════════════════════════════════════════════════

--- 2 x one-way delay to the furthest node, in ms (§5.1).
function M.lock_timeout_ms(plan)
  local max_delay = 0
  for _, n in ipairs(plan.nodes or {}) do
    if (n.delay or 0) > max_delay then max_delay = n.delay end
  end
  return constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * max_delay * 1000
end

local function participants(plan)
  local out = {}
  for _, n in ipairs(plan.nodes or {}) do
    if n.role == "PARTICIPANT" then out[#out + 1] = n end
  end
  return out
end

local function quorum_count(plan, quorum)
  local total = #participants(plan)
  if quorum == "majority" then return total // 2 + 1 end
  if type(quorum) == "number" then
    return math.min(math.max(quorum, 1), total)
  end
  return total  -- "all" (default)
end

--- Create a session context in DRAFT state. `plan_id` is supplied by the
-- caller (make_plan_id) so this module stays pure.
-- opts.quorum: "all" (default) | "majority" | number.
function M.create_session(plan, plan_id, opts)
  opts = opts or {}
  return {
    state = "DRAFT",
    plan = plan,
    plan_id = plan_id,
    session_root_plan_id = plan_id,
    plan_version = plan.planVersion or 1,
    lock = nil,
    lock_started_at_ms = nil,
    lock_timeout_ms = M.lock_timeout_ms(plan),
    confirmations = {},
    mismatched = {},
    quorum_threshold = quorum_count(plan, opts.quorum),
    subset = nil,
    degraded_reasons = {},
    resume_state = nil,
    pending_amendment = nil,
  }
end

local function copy_ctx(c)
  local n = shallow_copy(c)
  n.confirmations = shallow_copy(c.confirmations)
  n.mismatched = list_copy(c.mismatched)
  n.degraded_reasons = list_copy(c.degraded_reasons)
  n.subset = c.subset and list_copy(c.subset) or nil
  return n
end

local function confirmed_subset(ctx)
  local host = ctx.plan.nodes[1]
  local confirmed = {}
  for idx, n in ipairs(participants(ctx.plan)) do
    if ctx.confirmations[n.id] == ctx.plan_id then
      confirmed[#confirmed + 1] = { node = n, idx = idx }
    end
  end
  -- Stable ascending-delay sort (declaration order breaks ties).
  table.sort(confirmed, function(a, b)
    local da, db = a.node.delay or 0, b.node.delay or 0
    if da ~= db then return da < db end
    return a.idx < b.idx
  end)
  local out = { host.id }
  for _, c in ipairs(confirmed) do out[#out + 1] = c.node.id end
  return out
end

local function full_lock_reached(ctx)
  for _, n in ipairs(participants(ctx.plan)) do
    if ctx.confirmations[n.id] ~= ctx.plan_id then return false end
  end
  return true
end

local function quorum_reached(ctx)
  local count = 0
  for _, n in ipairs(participants(ctx.plan)) do
    if ctx.confirmations[n.id] == ctx.plan_id then count = count + 1 end
  end
  return count >= ctx.quorum_threshold
end

-- Declared one-way delay: v3 pair-matrix HOST row, else node.delay.
local function declared_delay_s(plan, node_id)
  local node
  for _, n in ipairs(plan.nodes or {}) do
    if n.id == node_id then node = n end
  end
  if not node then return nil end
  if type(plan.delays) == "table" then
    local host_id = plan.nodes[1].id
    local pair = { host_id, node_id }
    table.sort(pair)
    local key = pair[1] .. "|" .. pair[2]
    if type(plan.delays[key]) == "number" then return plan.delays[key] end
  end
  return node.delay or 0
end

local function invalid_effect(ctx, event)
  return {
    kind = "notify", level = "warn", code = "INVALID_EVENT",
    detail = tostring(event.type) .. " ignored in state " .. ctx.state,
  }
end

local function moved(ctx, to, event, effects, detail)
  local entry = {
    type = "state_transition",
    from = ctx.state,
    to = to,
    event = event.type,
    atMs = event.nowMs,
    detail = detail,
  }
  local next_ctx = copy_ctx(ctx)
  next_ctx.state = to
  local all = { { kind = "audit", entry = entry } }
  for _, e in ipairs(effects or {}) do all[#all + 1] = e end
  return { ctx = next_ctx, effects = all }
end

local function unchanged(ctx, effects)
  return { ctx = ctx, effects = effects or {} }
end

local function degrade(ctx, event, reason, extra)
  local next_ctx = copy_ctx(ctx)
  next_ctx.degraded_reasons[#next_ctx.degraded_reasons + 1] = reason
  local effects = {
    { kind = "notify", level = "warn", code = "DEGRADED", detail = reason },
    { kind = "escalate", code = "DEGRADED", detail = reason },
  }
  for _, e in ipairs(extra or {}) do effects[#effects + 1] = e end
  if ctx.state == "DEGRADED" then
    return unchanged(next_ctx, { effects[1] })  -- already degraded: notify only
  end
  return moved(next_ctx, "DEGRADED", event, effects, reason)
end

--- Advance the session state machine. Pure and time-injected: every event
-- carries `nowMs`; same (ctx, event) always yields the same result.
-- @param ctx table  from create_session / a previous transition
-- @param event table  { type = ..., nowMs = ..., ... }
-- @return table  { ctx = <new ctx>, effects = { { kind = ... }, ... } }
function M.transition(ctx, event)
  local etype = event.type

  if etype == "START_LOCK" then
    if ctx.state ~= "DRAFT" then return unchanged(ctx, { invalid_effect(ctx, event) }) end
    local host_id = ctx.plan.nodes[1].id
    local next_ctx = copy_ctx(ctx)
    next_ctx.lock_started_at_ms = event.nowMs
    next_ctx.confirmations[host_id] = ctx.plan_id
    return moved(next_ctx, "LOCKING", event, {})

  elseif etype == "PLAN_CONFIRM" then
    if ctx.state ~= "LOCKING" and ctx.state ~= "DEGRADED" then
      return unchanged(ctx, { invalid_effect(ctx, event) })
    end
    local next_ctx = copy_ctx(ctx)
    next_ctx.confirmations[event.nodeId] = event.planId
    if event.planId ~= ctx.plan_id then
      local mm = {}
      for _, id in ipairs(ctx.mismatched) do
        if id ~= event.nodeId then mm[#mm + 1] = id end
      end
      mm[#mm + 1] = event.nodeId
      next_ctx.mismatched = mm
      return unchanged(next_ctx, { {
        kind = "notify", level = "warn", code = "PLANID_MISMATCH",
        detail = event.nodeId .. " confirmed " .. event.planId
          .. ", expected " .. ctx.plan_id .. " (resolve per §5.5)",
      } })
    end
    local mm = {}
    for _, id in ipairs(ctx.mismatched) do
      if id ~= event.nodeId then mm[#mm + 1] = id end
    end
    next_ctx.mismatched = mm
    if full_lock_reached(next_ctx) then
      local locked = copy_ctx(next_ctx)
      locked.lock = "FULL"
      locked.subset = nil
      -- Late full confirmation recovers a DEGRADED quorum lock (§5.2).
      return moved(locked, "LOCKED", event, { {
        kind = "notify", level = "info", code = "LOCKED",
        detail = "full lock achieved",
      } })
    end
    return unchanged(next_ctx)

  elseif etype == "TICK" then
    if ctx.state ~= "LOCKING" then return unchanged(ctx) end
    if ctx.lock_started_at_ms == nil then return unchanged(ctx) end
    if event.nowMs - ctx.lock_started_at_ms < ctx.lock_timeout_ms then
      return unchanged(ctx)
    end
    -- Lock timeout expired (§5.1).
    if quorum_reached(ctx) then
      local subset = confirmed_subset(ctx)
      local next_ctx = copy_ctx(ctx)
      next_ctx.lock = "QUORUM"
      next_ctx.subset = subset
      local missing = {}
      for _, n in ipairs(participants(ctx.plan)) do
        if ctx.confirmations[n.id] ~= ctx.plan_id then missing[#missing + 1] = n.id end
      end
      return degrade(next_ctx, event,
        "quorum lock with subset [" .. table.concat(subset, ",")
          .. "]; unconfirmed: [" .. table.concat(missing, ",") .. "]")
    end
    return degrade(ctx, event, "plan-lock timeout without quorum")

  elseif etype == "SESSION_START" then
    if ctx.state == "LOCKED" then return moved(ctx, "ACTIVE", event, {}) end
    if ctx.state == "DEGRADED" and ctx.lock ~= nil then
      -- §5.2: escalation to HOST required before TX.
      return unchanged(ctx, { {
        kind = "escalate", code = "DEGRADED_START",
        detail = "session start requested while DEGRADED; HOST decision required",
      } })
    end
    return unchanged(ctx, { invalid_effect(ctx, event) })

  elseif etype == "DELAY_MEASURED" then
    if ctx.state ~= "ACTIVE" and ctx.state ~= "LOCKED" and ctx.state ~= "DEGRADED" then
      return unchanged(ctx)
    end
    local declared = declared_delay_s(ctx.plan, event.nodeId)
    if declared == nil then return unchanged(ctx, { invalid_effect(ctx, event) }) end
    local deviation = math.abs(event.measuredDelayS - declared)
    if deviation > constants.DELAY_VIOLATION_DEGRADED_S then
      return degrade(ctx, event,
        "delay violation " .. event.nodeId .. ": measured " .. event.measuredDelayS
          .. "s vs declared " .. declared .. "s (>"
          .. constants.DELAY_VIOLATION_DEGRADED_S .. "s)")
    end
    if deviation > constants.DELAY_VIOLATION_WARN_S then
      return unchanged(ctx, { {
        kind = "notify", level = "warn", code = "DELAY_VIOLATION",
        detail = event.nodeId .. ": measured " .. event.measuredDelayS
          .. "s vs declared " .. declared .. "s",
      } })
    end
    return unchanged(ctx)

  elseif etype == "EOK_OVERRIDE" then
    if ctx.state == "COMPLETE" or ctx.state == "ABORTED" then return unchanged(ctx) end
    if not event.verified then
      return unchanged(ctx, { {
        kind = "notify", level = "error", code = "OVERRIDE_REJECTED",
        detail = event.reason or "override failed verification",
      } })
    end
    if ctx.state == "EMERGENCY_HOLD" then return unchanged(ctx) end
    local next_ctx = copy_ctx(ctx)
    next_ctx.resume_state = ctx.state
    return moved(next_ctx, "EMERGENCY_HOLD", event, { {
      kind = "notify", level = "error", code = "EMERGENCY_HOLD",
      detail = event.reason or "verified EOK override",
    } })

  elseif etype == "AMENDMENT_PROPOSED" then
    if ctx.state ~= "ACTIVE" and ctx.state ~= "LOCKED" and ctx.state ~= "DEGRADED" then
      return unchanged(ctx, { invalid_effect(ctx, event) })
    end
    if event.planVersion ~= ctx.plan_version + 1 then
      return unchanged(ctx, { {
        kind = "notify", level = "error", code = "AMENDMENT_REJECTED",
        detail = "planVersion " .. tostring(event.planVersion)
          .. " != " .. ctx.plan_version .. " + 1",
      } })
    end
    -- Delta re-lock (§6.4): timeout scoped to the furthest affected node.
    local affected = event.affectedNodeIds or {}
    local affected_set = {}
    for _, id in ipairs(affected) do affected_set[id] = true end
    local max_delay = 0
    for _, n in ipairs(ctx.plan.nodes or {}) do
      if affected_set[n.id] and (n.delay or 0) > max_delay then max_delay = n.delay end
    end
    local next_ctx = copy_ctx(ctx)
    next_ctx.pending_amendment = {
      plan_id = event.planId,
      plan_version = event.planVersion,
      affected_node_ids = list_copy(affected),
      confirmed = {},
      proposed_at_ms = event.nowMs,
      timeout_ms = constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * max_delay * 1000,
    }
    return unchanged(next_ctx, { {
      kind = "notify", level = "info", code = "AMENDMENT_PROPOSED",
      detail = "plan " .. event.planId .. " v" .. event.planVersion
        .. "; awaiting [" .. table.concat(affected, ",") .. "]",
    } })

  elseif etype == "AMENDMENT_CONFIRMED" then
    local pa = ctx.pending_amendment
    if not pa or event.planId ~= pa.plan_id then
      return unchanged(ctx, { invalid_effect(ctx, event) })
    end
    local is_affected = false
    for _, id in ipairs(pa.affected_node_ids) do
      if id == event.nodeId then is_affected = true end
    end
    if not is_affected then return unchanged(ctx) end
    local confirmed = {}
    for _, id in ipairs(pa.confirmed) do
      if id ~= event.nodeId then confirmed[#confirmed + 1] = id end
    end
    confirmed[#confirmed + 1] = event.nodeId
    if #confirmed < #pa.affected_node_ids then
      local next_ctx = copy_ctx(ctx)
      next_ctx.pending_amendment = {
        plan_id = pa.plan_id,
        plan_version = pa.plan_version,
        affected_node_ids = list_copy(pa.affected_node_ids),
        confirmed = confirmed,
        proposed_at_ms = pa.proposed_at_ms,
        timeout_ms = pa.timeout_ms,
      }
      return unchanged(next_ctx)
    end
    -- All affected nodes confirmed -- the amendment applies. The caller
    -- swaps ctx.plan for the verified successor plan.
    local next_ctx = copy_ctx(ctx)
    next_ctx.plan_id = pa.plan_id
    next_ctx.plan_version = pa.plan_version
    next_ctx.pending_amendment = nil
    return unchanged(next_ctx, { {
      kind = "notify", level = "info", code = "AMENDMENT_APPLIED",
      detail = "plan " .. pa.plan_id .. " v" .. pa.plan_version
        .. " in effect (root " .. ctx.session_root_plan_id .. ")",
    } })

  elseif etype == "HOST_DECISION" then
    if event.decision == "abort" then
      if ctx.state == "COMPLETE" or ctx.state == "ABORTED" then return unchanged(ctx) end
      return moved(ctx, "ABORTED", event, {})
    end
    if event.decision == "resume" and ctx.state == "EMERGENCY_HOLD" then
      local back = ctx.resume_state or "ACTIVE"
      local next_ctx = copy_ctx(ctx)
      next_ctx.resume_state = nil
      return moved(next_ctx, back, event, {})
    end
    if event.decision == "continue" and ctx.state == "DEGRADED" then
      -- §5.2: HOST elects to continue with the confirmed subset.
      local detail = ctx.subset
        and ("continuing with subset [" .. table.concat(ctx.subset, ",") .. "]")
        or "continuing despite degraded condition"
      return moved(ctx, "ACTIVE", event, { {
        kind = "notify", level = "warn", code = "CONTINUE_DEGRADED",
        detail = detail,
      } })
    end
    return unchanged(ctx, { invalid_effect(ctx, event) })

  elseif etype == "SESSION_END" then
    if ctx.state == "ACTIVE" or ctx.state == "DEGRADED" then
      return moved(ctx, "COMPLETE", event, {})
    end
    return unchanged(ctx, { invalid_effect(ctx, event) })
  end

  return unchanged(ctx, { invalid_effect(ctx, event) })
end

-- ═════════════════════════════════════════════════════════════════════════
-- 3. Amendment-chain verify (§6.4, LTX-SECURITY.md §7.6)
-- ═════════════════════════════════════════════════════════════════════════

--- SHA-256 hex of the RFC 8785 canonical JSON of a plan. Always the
-- canonical hash -- never the legacy v2 polynomial planId hash.
function M.plan_hash(plan)
  return security.sha256_hex(canonical_json(plan))
end

--- Verify a TRANSITIONAL JSON COSE_Sign1 plan envelope
-- ({ plan, coseSign1 = { protected, unprotected = { kid }, payload,
-- signature } }) with real Ed25519 against a key cache of kid -> NIK.
-- @return boolean, string  valid, reason
function M.verify_plan_envelope(envelope, key_cache)
  if type(envelope) ~= "table" or type(envelope.coseSign1) ~= "table" then
    return false, "missing_cose_sign1"
  end
  local cs = envelope.coseSign1
  local kid = cs.unprotected and cs.unprotected.kid or ""
  if kid == "" then return false, "missing_kid" end
  local nik = lookup_nik(kid, key_cache)
  if not nik then return false, "key_not_in_cache" end
  if nik_expired(nik) then return false, "key_expired" end
  local sig_struct = canonical_json({ "Signature1", cs.protected, "", cs.payload })
  if not verify_bytes(sig_struct, cs.signature, nik) then
    return false, "signature_invalid"
  end
  if b64u_decode(cs.payload or "") ~= canonical_json(envelope.plan) then
    return false, "payload_mismatch"
  end
  return true, "ok"
end

--- Verify an amendment chain: chain[1] is the root plan, each later element
-- a successive amendment. Checks, per link: HOST signature against
-- `key_cache`, planVersion increment of exactly 1, and prevPlanHash equality
-- with the recomputed predecessor hash (LTX-SECURITY.md §7.6).
-- @return boolean, string  valid, reason
function M.verify_amendment_chain(chain, key_cache)
  if type(chain) ~= "table" or #chain == 0 then
    return false, "empty_chain"
  end
  for i, link in ipairs(chain) do
    local ok, reason = M.verify_plan_envelope(link, key_cache)
    if not ok then
      return false, "link_" .. (i - 1) .. "_" .. reason
    end
  end
  local root = chain[1].plan
  if root.prevPlanHash ~= nil then
    return false, "root_has_prev_hash"
  end
  local prev_plan = root
  local prev_version = root.planVersion or 1
  for i = 2, #chain do
    local p = chain[i].plan
    if p.v ~= 3 then return false, "link_" .. (i - 1) .. "_not_v3" end
    if (p.planVersion or 0) ~= prev_version + 1 then
      return false, "link_" .. (i - 1) .. "_version_gap"
    end
    if p.prevPlanHash ~= M.plan_hash(prev_plan) then
      return false, "link_" .. (i - 1) .. "_prev_hash_mismatch"
    end
    prev_plan = p
    prev_version = p.planVersion
  end
  return true, "ok"
end

-- ═════════════════════════════════════════════════════════════════════════
-- 4. Register entries + reducers (§9/§10, LTX-SECURITY.md §9.5/§9.6)
-- ═════════════════════════════════════════════════════════════════════════

--- Verify a register entry signature (Ed25519 over the canonical JSON of the
-- entry without `sig`) against a key cache mapping the entry's nodeId to its
-- NIK.
-- @return boolean, string  valid, reason
function M.verify_register_entry(entry, key_cache)
  if type(entry) ~= "table" or type(entry.sig) ~= "string" or entry.sig == "" then
    return false, "missing_sig"
  end
  local nik = (key_cache or {})[entry.nodeId]
  if not nik then return false, "key_not_in_cache" end
  local unsigned = {}
  for k, v in pairs(entry) do
    if k ~= "sig" then unsigned[k] = v end
  end
  if verify_bytes(canonical_json(unsigned), entry.sig, nik) then
    return true, "ok"
  end
  return false, "signature_invalid"
end

--- De-duplicate by (nodeId, seq) and sort into the §8.2 total order
-- (timestamp, nodeId, seq).
function M.order_entries(entries)
  local seen = {}
  local unique = {}
  for _, e in ipairs(entries or {}) do
    local key = tostring(e.nodeId) .. " " .. tostring(e.seq)
    if not seen[key] then
      seen[key] = true
      unique[#unique + 1] = e
    end
  end
  table.sort(unique, function(a, b)
    if a.timestamp ~= b.timestamp then return a.timestamp < b.timestamp end
    if a.nodeId ~= b.nodeId then return a.nodeId < b.nodeId end
    return a.seq < b.seq
  end)
  return unique
end

-- §8.2 conflict rule: higher version wins; tie -> lowest editor nodeId.
local function conflict_wins(in_version, in_editor, cur_version, cur_editor)
  if in_version ~= cur_version then return in_version > cur_version end
  return in_editor < cur_editor
end

--- Reduce question register state from log entries (§9.4). Pure: identical
-- entry sets (in any input order) produce identical state.
-- @return table  { by_id = { [qid] = state }, superseded = { entryId, ... } }
function M.reduce_questions(entries)
  local by_id = {}
  local winners = {}
  local superseded = {}

  for _, e in ipairs(M.order_entries(entries)) do
    local content = e.content or {}
    if e.type == "question" then
      local qid = e.entryId
      if by_id[qid] then
        superseded[#superseded + 1] = e.entryId
      else
        winners[qid] = { version = 1, editor = e.nodeId, entry_id = e.entryId }
        by_id[qid] = {
          qid = qid,
          text = tostring(content.text or ""),
          submitter = e.nodeId,
          urgency = content.urgency and tostring(content.urgency) or nil,
          intendedWindow = content.intendedWindow and tostring(content.intendedWindow) or nil,
          status = "OPEN",
          version = 1,
        }
      end
    elseif e.type == "question_response" then
      local qid = tostring(content.qid or "")
      local q = by_id[qid]
      if not q then
        superseded[#superseded + 1] = e.entryId
      else
        local version = content.version or (q.version + 1)
        local current = winners[qid]
        if current and not conflict_wins(version, e.nodeId, current.version, current.editor) then
          superseded[#superseded + 1] = e.entryId
        else
          if current and current.entry_id ~= q.qid then
            superseded[#superseded + 1] = current.entry_id
          end
          winners[qid] = { version = version, editor = e.nodeId, entry_id = e.entryId }
          q.status = content.status == "WITHDRAWN" and "WITHDRAWN" or "ANSWERED"
          if content.response ~= nil then q.response = tostring(content.response) end
          q.responder = e.nodeId
          q.version = version
        end
      end
    end
  end
  return { by_id = by_id, superseded = superseded }
end

local ACTION_STATUSES = { PROPOSED = true, ACCEPTED = true, REJECTED = true, DONE = true }

--- Reduce action register state from log entries (§10.2).
-- @return table  { by_id = { [aid] = state }, superseded = { entryId, ... } }
function M.reduce_actions(entries)
  local by_id = {}
  local winners = {}
  local superseded = {}

  for _, e in ipairs(M.order_entries(entries)) do
    local content = e.content or {}
    if e.type == "action" then
      local aid = e.entryId
      if by_id[aid] then
        superseded[#superseded + 1] = e.entryId
      else
        winners[aid] = { version = 1, editor = e.nodeId, entry_id = e.entryId }
        by_id[aid] = {
          aid = aid,
          description = tostring(content.description or ""),
          owner = content.owner and tostring(content.owner) or nil,
          dueTimeUTC = content.dueTimeUTC and tostring(content.dueTimeUTC) or nil,
          originWindow = content.originWindow and tostring(content.originWindow) or nil,
          status = "PROPOSED",
          version = 1,
        }
      end
    elseif e.type == "action_update" then
      local aid = tostring(content.aid or "")
      local a = by_id[aid]
      if not a then
        superseded[#superseded + 1] = e.entryId
      else
        local version = content.version or (a.version + 1)
        local current = winners[aid]
        if current and not conflict_wins(version, e.nodeId, current.version, current.editor) then
          superseded[#superseded + 1] = e.entryId
        else
          if current and current.entry_id ~= a.aid then
            superseded[#superseded + 1] = current.entry_id
          end
          winners[aid] = { version = version, editor = e.nodeId, entry_id = e.entryId }
          if ACTION_STATUSES[content.status] then a.status = content.status end
          if content.description ~= nil then a.description = tostring(content.description) end
          if content.owner ~= nil then a.owner = tostring(content.owner) end
          if content.dueTimeUTC ~= nil then a.dueTimeUTC = tostring(content.dueTimeUTC) end
          a.version = version
        end
      end
    end
  end
  return { by_id = by_id, superseded = superseded }
end

-- ── Merkle audit-log root (RFC 9162 style) ──────────────────────────────────
-- Leaf: SHA-256(0x00 || canonicalJSON(entry)); node: SHA-256(0x01 || l || r);
-- empty root: 32 zero bytes.

local function merkle_root_of(leaves, lo, hi)
  local n = hi - lo + 1
  if n <= 0 then return string.rep("\0", 32) end
  if n == 1 then return leaves[lo] end
  -- Split at the largest power of two strictly less than the leaf count.
  local mid = 1
  while mid * 2 < n do mid = mid * 2 end
  return security.sha256_raw("\1"
    .. merkle_root_of(leaves, lo, lo + mid - 1)
    .. merkle_root_of(leaves, lo + mid, hi))
end

--- Merkle log root (hex) over the §8.2-ordered entries.
function M.entries_root(entries)
  local ordered = M.order_entries(entries)
  local leaves = {}
  for i, e in ipairs(ordered) do
    leaves[i] = security.sha256_raw("\0" .. canonical_json(e))
  end
  local root = merkle_root_of(leaves, 1, #leaves)
  return (root:gsub('.', function(c)
    return string.format('%02x', string.byte(c))
  end))
end

-- ═════════════════════════════════════════════════════════════════════════
-- 5. Deterministic CBOR (RFC 8949) + COSE_Sign1 verify (RFC 9052)
-- ═════════════════════════════════════════════════════════════════════════
--
-- Value model:
--   nil-able null      -> M.CBOR_NULL sentinel
--   boolean            -> boolean
--   integer            -> Lua integer
--   text string        -> Lua string
--   byte string        -> { bstr = <Lua string> }
--   array              -> list-style table
--   map                -> { map = { { k1, v1 }, { k2, v2 }, ... } }
--   tag                -> { tag = <n>, value = <v> }
-- Floats and indefinite lengths are rejected.

M.CBOR_NULL = setmetatable({}, { __tostring = function() return "cbor:null" end })

M.COSE_SIGN1_TAG = 18
M.COSE_ALG_ED25519 = -19

local function cbor_head(major, arg)
  if arg < 24 then
    return string.char((major << 5) | arg)
  elseif arg < 0x100 then
    return string.char((major << 5) | 24, arg)
  elseif arg < 0x10000 then
    return string.char((major << 5) | 25, (arg >> 8) & 0xff, arg & 0xff)
  elseif arg < 0x100000000 then
    return string.char((major << 5) | 26,
      (arg >> 24) & 0xff, (arg >> 16) & 0xff, (arg >> 8) & 0xff, arg & 0xff)
  end
  local out = { string.char((major << 5) | 27) }
  for shift = 56, 0, -8 do
    out[#out + 1] = string.char((arg >> shift) & 0xff)
  end
  return table.concat(out)
end

--- Encode a value (see the module value model) to deterministic CBOR bytes
-- (RFC 8949 §4.2.1): definite lengths, shortest-form heads, map keys sorted
-- bytewise by their encoded form.
-- @return string|nil, string|nil
function M.cbor_encode(value)
  if value == M.CBOR_NULL then return "\246" end
  local t = type(value)
  if t == "boolean" then return value and "\245" or "\244" end
  if t == "number" then
    if math.type(value) ~= "integer" then
      return nil, "cbor: only integers supported"
    end
    if value >= 0 then return cbor_head(0, value) end
    return cbor_head(1, -value - 1)
  end
  if t == "string" then
    return cbor_head(3, #value) .. value
  end
  if t == "table" then
    if value.bstr ~= nil then
      return cbor_head(2, #value.bstr) .. value.bstr
    end
    if value.tag ~= nil then
      local inner, err = M.cbor_encode(value.value)
      if not inner then return nil, err end
      return cbor_head(6, value.tag) .. inner
    end
    if value.map ~= nil then
      local encoded = {}
      for _, pair in ipairs(value.map) do
        local k, kerr = M.cbor_encode(pair[1])
        if not k then return nil, kerr end
        local v, verr = M.cbor_encode(pair[2])
        if not v then return nil, verr end
        encoded[#encoded + 1] = { k, v }
      end
      table.sort(encoded, function(a, b) return a[1] < b[1] end)
      local out = { cbor_head(5, #encoded) }
      for _, pair in ipairs(encoded) do
        out[#out + 1] = pair[1]
        out[#out + 1] = pair[2]
      end
      return table.concat(out)
    end
    -- plain list-style table -> array
    local out = { cbor_head(4, #value) }
    for _, v in ipairs(value) do
      local inner, err = M.cbor_encode(v)
      if not inner then return nil, err end
      out[#out + 1] = inner
    end
    return table.concat(out)
  end
  return nil, "cbor: unsupported type " .. t
end

local function cbor_read_head(buf, pos)
  local initial = string.byte(buf, pos)
  if not initial then return nil, nil, nil, "cbor: truncated" end
  pos = pos + 1
  local major = initial >> 5
  local info = initial & 0x1f
  if info < 24 then return major, info, pos end
  local extra
  if info == 24 then extra = 1
  elseif info == 25 then extra = 2
  elseif info == 26 then extra = 4
  elseif info == 27 then extra = 8
  else return nil, nil, nil, "cbor: indefinite lengths not supported" end
  if pos + extra - 1 > #buf then return nil, nil, nil, "cbor: truncated" end
  local arg = 0
  for _ = 1, extra do
    arg = (arg << 8) | string.byte(buf, pos)
    pos = pos + 1
  end
  return major, arg, pos
end

local function cbor_decode_item(buf, pos)
  local first = string.byte(buf, pos)
  if not first then return nil, nil, "cbor: truncated" end
  if first == 0xf6 then return M.CBOR_NULL, pos + 1 end
  if first == 0xf5 then return true, pos + 1 end
  if first == 0xf4 then return false, pos + 1 end

  local major, arg, next_pos, err = cbor_read_head(buf, pos)
  if not major then return nil, nil, err end
  pos = next_pos

  if major == 0 then
    return arg, pos
  elseif major == 1 then
    return -arg - 1, pos
  elseif major == 2 or major == 3 then
    if pos + arg - 1 > #buf then return nil, nil, "cbor: truncated string" end
    local s = string.sub(buf, pos, pos + arg - 1)
    pos = pos + arg
    if major == 2 then return { bstr = s }, pos end
    return s, pos
  elseif major == 4 then
    local out = {}
    for i = 1, arg do
      local v
      v, pos, err = cbor_decode_item(buf, pos)
      if err then return nil, nil, err end
      out[i] = v
    end
    return out, pos
  elseif major == 5 then
    local pairs_out = {}
    for i = 1, arg do
      local k, v
      k, pos, err = cbor_decode_item(buf, pos)
      if err then return nil, nil, err end
      v, pos, err = cbor_decode_item(buf, pos)
      if err then return nil, nil, err end
      pairs_out[i] = { k, v }
    end
    return { map = pairs_out }, pos
  elseif major == 6 then
    local v
    v, pos, err = cbor_decode_item(buf, pos)
    if err then return nil, nil, err end
    return { tag = arg, value = v }, pos
  end
  return nil, nil, "cbor: unsupported major type " .. major .. " / simple value"
end

--- Decode deterministic CBOR bytes (see the module value model). Rejects
-- floats, indefinite lengths and trailing bytes.
-- @return value|nil, string|nil
function M.cbor_decode(bytes)
  local value, pos, err = cbor_decode_item(bytes, 1)
  if err then return nil, err end
  if pos ~= #bytes + 1 then return nil, "cbor: trailing bytes" end
  return value
end

local function cbor_map_get(map_value, key)
  if type(map_value) ~= "table" or type(map_value.map) ~= "table" then return nil end
  for _, pair in ipairs(map_value.map) do
    if pair[1] == key then return pair[2] end
  end
  return nil
end

--- Verify a CBOR COSE_Sign1 plan envelope
-- ({ plan = ..., coseSign1CborB64 = ... }) against the key cache. Rejects
-- non-Ed25519 algorithms (including the deprecated -8) and payloads that do
-- not match the accompanying plan object.
-- @return boolean, string  valid, reason
function M.verify_plan_cose(envelope, key_cache)
  if type(envelope) ~= "table" or type(envelope.coseSign1CborB64) ~= "string" then
    return false, "missing_cose_sign1"
  end
  local decoded, err = M.cbor_decode(b64u_decode(envelope.coseSign1CborB64))
  if not decoded then return false, "cbor_decode_failed" end
  if type(decoded) ~= "table" or decoded.tag ~= M.COSE_SIGN1_TAG then
    return false, "not_cose_sign1"
  end
  local arr = decoded.value
  if type(arr) ~= "table" or #arr ~= 4 then
    return false, "malformed_cose_sign1"
  end
  local protected_bstr = arr[1]
  local unprotected = arr[2]
  local payload_bstr = arr[3]
  local sig_bstr = arr[4]
  if type(protected_bstr) ~= "table" or not protected_bstr.bstr
      or type(payload_bstr) ~= "table" or not payload_bstr.bstr
      or type(sig_bstr) ~= "table" or not sig_bstr.bstr then
    return false, "malformed_cose_sign1"
  end

  local protected_map, perr = M.cbor_decode(protected_bstr.bstr)
  if not protected_map then return false, "protected_decode_failed" end
  if cbor_map_get(protected_map, 1) ~= M.COSE_ALG_ED25519 then
    return false, "unsupported_alg"
  end

  local kid_value = cbor_map_get(unprotected, 4)
  local kid = ""
  if type(kid_value) == "table" and kid_value.bstr then
    kid = b64u_encode(kid_value.bstr)
  elseif type(kid_value) == "string" then
    kid = kid_value
  end
  if kid == "" then return false, "missing_kid" end

  local nik = lookup_nik(kid, key_cache)
  if not nik then return false, "key_not_in_cache" end
  if nik_expired(nik) then return false, "key_expired" end

  local sig_struct = M.cbor_encode({
    "Signature1", protected_bstr, { bstr = "" }, payload_bstr,
  })
  local pub = nik_raw_pub(nik)
  if not pub or #sig_bstr.bstr ~= 64
      or not ed25519.verify(sig_struct, sig_bstr.bstr, pub) then
    return false, "signature_invalid"
  end

  if envelope.plan ~= nil and payload_bstr.bstr ~= canonical_json(envelope.plan) then
    return false, "payload_mismatch"
  end
  return true, "ok"
end

return M
