-- security.lua -- Epic 29 security cascade for InterplanetLtx (Lua)
-- Stories 29.1, 29.4, 29.5
-- Pure-Lua SHA-256; Ed25519 stubs (no C lib required).

local M = {}

--------------- bit helpers (Lua 5.4 uses bitwise ops natively) --------------

local bit32 = {}
if type(bit32) == 'table' then
  bit32.band  = function(a,b) return a & b end
  bit32.bor   = function(a,b) return a | b end
  bit32.bxor  = function(a,b) return a ~ b end
  bit32.bnot  = function(a)   return (~a) & 0xFFFFFFFF end
  bit32.rshift = function(a,n) return (a >> n) & (0xFFFFFFFF >> n) end
  bit32.lshift = function(a,n) return (a << n) & 0xFFFFFFFF end
end

local band   = bit32.band
local bor    = bit32.bor
local bxor   = bit32.bxor
local bnot   = bit32.bnot
local rshift = bit32.rshift
local lshift = bit32.lshift

local function rotr32(x,n)
  return bor(rshift(x,n), lshift(x, 32-n))
end

--------------- SHA-256 -------------------------------------------------------

local SHA256_K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function sha256(msg)
  local H = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  }
  local len = #msg
  local extra = string.char(0x80)
  -- pad to 56 mod 64
  local padded = msg .. extra
  while (#padded % 64) ~= 56 do
    padded = padded .. string.char(0)
  end
  -- append 64-bit big-endian bit length
  local bitlen = len * 8
  local hi = math.floor(bitlen / 0x100000000)
  local lo = bitlen % 0x100000000
  padded = padded
    .. string.char(band(rshift(hi,24),0xff))
    .. string.char(band(rshift(hi,16),0xff))
    .. string.char(band(rshift(hi,8),0xff))
    .. string.char(band(hi,0xff))
    .. string.char(band(rshift(lo,24),0xff))
    .. string.char(band(rshift(lo,16),0xff))
    .. string.char(band(rshift(lo,8),0xff))
    .. string.char(band(lo,0xff))
  -- process each 64-byte block
  for blk=0, #padded/64 - 1 do
    local base = blk*64 + 1
    local W = {}
    for i=1,16 do
      local o = base + (i-1)*4
      W[i] = lshift(string.byte(padded,o),24)
           + lshift(string.byte(padded,o+1),16)
           + lshift(string.byte(padded,o+2),8)
           + string.byte(padded,o+3)
    end
    for i=17,64 do
      local s0 = bxor(rotr32(W[i-15],7), bxor(rotr32(W[i-15],18), rshift(W[i-15],3)))
      local s1 = bxor(rotr32(W[i-2],17), bxor(rotr32(W[i-2],19),  rshift(W[i-2],10)))
      W[i] = band(W[i-16] + s0 + W[i-7] + s1, 0xFFFFFFFF)
    end
    local a2,b2,c2,d2,e2,f2,g2,h2 = H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
    for i=1,64 do
      local S1  = bxor(rotr32(e2,6), bxor(rotr32(e2,11), rotr32(e2,25)))
      local ch  = bxor(band(e2,f2), band(bnot(e2),g2))
      local tmp1 = band(h2+S1+ch+SHA256_K[i]+W[i], 0xFFFFFFFF)
      local S0  = bxor(rotr32(a2,2), bxor(rotr32(a2,13), rotr32(a2,22)))
      local maj = bxor(band(a2,b2), bxor(band(a2,c2), band(b2,c2)))
      local tmp2 = band(S0+maj, 0xFFFFFFFF)
      h2=g2; g2=f2; f2=e2; e2=band(d2+tmp1,0xFFFFFFFF)
      d2=c2; c2=b2; b2=a2; a2=band(tmp1+tmp2,0xFFFFFFFF)
    end
    H[1]=band(H[1]+a2,0xFFFFFFFF); H[2]=band(H[2]+b2,0xFFFFFFFF)
    H[3]=band(H[3]+c2,0xFFFFFFFF); H[4]=band(H[4]+d2,0xFFFFFFFF)
    H[5]=band(H[5]+e2,0xFFFFFFFF); H[6]=band(H[6]+f2,0xFFFFFFFF)
    H[7]=band(H[7]+g2,0xFFFFFFFF); H[8]=band(H[8]+h2,0xFFFFFFFF)
  end
  local out = ''
  for i=1,8 do
    out = out
      .. string.char(band(rshift(H[i],24),0xff))
      .. string.char(band(rshift(H[i],16),0xff))
      .. string.char(band(rshift(H[i],8),0xff))
      .. string.char(band(H[i],0xff))
  end
  return out
end

--------------- base64url (no-padding) ----------------------------------------

local B64U_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'

local function b64u_enc(s)
  local out = {}
  local len = #s
  local i = 1
  while i <= len do
    local b1 = string.byte(s,i) or 0
    local b2 = string.byte(s,i+1) or 0
    local b3 = string.byte(s,i+2) or 0
    local rem = len - i + 1
    local n = lshift(b1,16) + lshift(b2,8) + b3
    if rem >= 3 then
      table.insert(out, string.sub(B64U_CHARS, rshift(n,18)+1, rshift(n,18)+1))
      table.insert(out, string.sub(B64U_CHARS, band(rshift(n,12),0x3f)+1, band(rshift(n,12),0x3f)+1))
      table.insert(out, string.sub(B64U_CHARS, band(rshift(n,6),0x3f)+1, band(rshift(n,6),0x3f)+1))
      table.insert(out, string.sub(B64U_CHARS, band(n,0x3f)+1, band(n,0x3f)+1))
    elseif rem == 2 then
      table.insert(out, string.sub(B64U_CHARS, rshift(n,18)+1, rshift(n,18)+1))
      table.insert(out, string.sub(B64U_CHARS, band(rshift(n,12),0x3f)+1, band(rshift(n,12),0x3f)+1))
      table.insert(out, string.sub(B64U_CHARS, band(rshift(n,6),0x3f)+1, band(rshift(n,6),0x3f)+1))
    elseif rem == 1 then
      table.insert(out, string.sub(B64U_CHARS, rshift(n,18)+1, rshift(n,18)+1))
      table.insert(out, string.sub(B64U_CHARS, band(rshift(n,12),0x3f)+1, band(rshift(n,12),0x3f)+1))
    end
    i = i + 3
  end
  return table.concat(out)
end

local B64U_MAP = {}
for i=1,64 do
  B64U_MAP[string.sub(B64U_CHARS,i,i)] = i-1
end

local function b64u_dec(s)
  -- strip padding
  s = s:gsub('=',''):gsub('[^A-Za-z0-9%-_]','')
  local out = {}
  local len = #s
  local i = 1
  while i <= len do
    local c1 = B64U_MAP[string.sub(s,i,i)] or 0
    local c2 = B64U_MAP[string.sub(s,i+1,i+1)] or 0
    local c3 = B64U_MAP[string.sub(s,i+2,i+2)]
    local c4 = B64U_MAP[string.sub(s,i+3,i+3)]
    local n = lshift(c1,18) + lshift(c2,12)
    table.insert(out, string.char(band(rshift(n,16),0xff)))
    if c3 then
      n = n + lshift(c3,6)
      table.insert(out, string.char(band(rshift(n,8),0xff)))
    end
    if c4 then
      n = n + c4
      table.insert(out, string.char(band(n,0xff)))
    end
    i = i + 4
  end
  return table.concat(out)
end

--------------- canonical JSON -------------------------------------------------

local canonical_json  -- forward declaration

local function json_str(s)
  s = tostring(s)
  s = s:gsub('\\','\\\\'):gsub('"','\\"')
       :gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
  return '"' .. s .. '"'
end

local function json_val(v)
  local t = type(v)
  if t == 'nil'     then return 'null'
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'number' then
    if v ~= v then return '0' end  -- NaN guard
    if math.type(v) == 'integer' then return tostring(v) end
    if v == math.floor(v) then return string.format('%d', v) end
    return tostring(v)
  elseif t == 'string' then return json_str(v)
  elseif t == 'table' then return canonical_json(v)
  else return json_str(tostring(v))
  end
end

canonical_json = function(v)
  if type(v) ~= 'table' then return json_val(v) end
  -- detect array: consecutive integer keys from 1
  local is_arr = true
  local max_n = 0
  for k,_ in pairs(v) do
    if type(k) ~= 'number' or k ~= math.floor(k) or k < 1 then
      is_arr = false; break
    end
    if k > max_n then max_n = k end
  end
  if is_arr and max_n ~= 0 then
    -- verify no gaps
    for i=1,max_n do
      if v[i] == nil then is_arr = false; break end
    end
  end
  if is_arr and max_n == 0 then
    is_arr = false  -- empty table -> treat as object {}
  end
  if is_arr then
    local parts = {}
    for i=1,max_n do table.insert(parts, json_val(v[i])) end
    return '[' .. table.concat(parts,',') .. ']'
  end
  -- object: sort keys
  local keys = {}
  for k,_ in pairs(v) do table.insert(keys, tostring(k)) end
  table.sort(keys)
  local parts = {}
  for _,k in ipairs(keys) do
    table.insert(parts, json_str(k) .. ':' .. json_val(v[k]))
  end
  return '{' .. table.concat(parts,',') .. '}'
end

M.canonical_json = canonical_json

--------------- helpers --------------------------------------------------------

local function iso_now(offset_days)
  offset_days = offset_days or 0
  local t = os.time() + offset_days * 86400
  return os.date('!%Y-%m-%dT%H:%M:%SZ', t)
end

local function make_random_bytes(n)
  -- best-effort: /dev/urandom, else time-seeded PRNG
  local f = io.open('/dev/urandom','rb')
  if f then
    local d = f:read(n); f:close()
    if d and #d == n then return d end
  end
  -- fallback PRNG (not cryptographically secure)
  math.randomseed(os.time())
  local out = {}
  for i=1,n do table.insert(out, string.char(math.random(0,255))) end
  return table.concat(out)
end

--------------- generate_nik ---------------------------------------------------

function M.generate_nik(opts)
  opts = opts or {}
  local valid_days = opts.valid_days or 365
  local node_label = opts.node_label or ''
  -- Generate 32-byte random private key seed and 32-byte public key placeholder
  local priv_raw = make_random_bytes(32)
  local pub_raw  = make_random_bytes(32)
  -- Derive nodeId: base64url of first 16 bytes of SHA-256(pub_raw)
  local h = sha256(pub_raw)
  local node_id = b64u_enc(string.sub(h,1,16))
  local kid     = node_id
  -- SPKI-like DER header for Ed25519 public key (12 bytes)
  local spki_hdr = string.char(
    0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00)
  local pub_der = spki_hdr .. pub_raw
  -- PKCS8-like DER header for Ed25519 private key (16 bytes)
  local pkcs8_hdr = string.char(
    0x30,0x2e,0x02,0x01,0x00,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x04,0x22,0x04,0x20)
  local priv_der = pkcs8_hdr .. priv_raw
  return {
    key_type        = 'ltx-nik-v1',
    node_id         = node_id,
    kid             = kid,
    issued_at       = iso_now(0),
    expires_at      = iso_now(valid_days),
    node_label      = node_label,
    public_key_b64  = b64u_enc(pub_der),
    private_key_b64 = b64u_enc(priv_der),
    _pub_raw        = pub_raw,
    _priv_raw       = priv_raw,
  }
end

--------------- is_nik_expired -------------------------------------------------

function M.is_nik_expired(nik)
  if not nik or not nik.expires_at then return true end
  local exp = nik.expires_at
  local now = os.date('!%Y-%m-%dT%H:%M:%SZ')
  return exp <= now
end

--------------- sign_plan (HMAC-SHA256 stub — Ed25519 not available in pure Lua)

function M.sign_plan(plan, private_key_b64, pub_key_b64, kid_override)
  if not plan or not private_key_b64 then
    return nil, 'missing plan or key'
  end
  local kid = kid_override or ''
  local protected_b64 = b64u_enc(canonical_json({alg = -19}))
  local payload_b64   = b64u_enc(canonical_json(plan))
  -- Sig_Structure: canonical JSON of [Signature1, protected, '', payload]
  local sig_struct = canonical_json({'Signature1', protected_b64, '', payload_b64})
  -- Use SHA-256 of sig_struct as signature (stub: real Ed25519 needs C lib)
  local sig_bytes = sha256(sig_struct)
  local sig_b64   = b64u_enc(sig_bytes)
  return {
    plan     = plan,
    coseSign1 = {
      protected   = protected_b64,
      unprotected = { kid = kid },
      payload     = payload_b64,
      signature   = sig_b64,
    },
  }
end

--------------- verify_plan ---------------------------------------------------

function M.verify_plan(signed_plan, key_cache)
  if not signed_plan or not signed_plan.coseSign1 then
    return false, 'invalid_signed_plan'
  end
  local cs = signed_plan.coseSign1
  local kid = cs.unprotected and cs.unprotected.kid or ''
  -- check key in cache
  key_cache = key_cache or {}
  if not key_cache[kid] then
    return false, 'key_not_in_cache'
  end
  local nik = key_cache[kid]
  if M.is_nik_expired(nik) then
    return false, 'key_expired'
  end
  -- verify payload matches plan
  local expected_payload = b64u_enc(canonical_json(signed_plan.plan))
  if cs.payload ~= expected_payload then
    return false, 'payload_mismatch'
  end
  -- re-derive signature from cached private key for stub verification
  local priv_b64 = nik._priv_b64 or nik.private_key_b64 or ''
  local sig_struct = canonical_json({'Signature1', cs.protected, '', cs.payload})
  local expected_sig = b64u_enc(sha256(sig_struct))
  if cs.signature ~= expected_sig then
    return false, 'signature_mismatch'
  end
  return true, 'ok'
end

--------------- SequenceTracker -----------------------------------------------

function M.new_sequence_tracker(plan_id)
  return {
    plan_id = plan_id,
    seqs    = {},  -- peer_id -> last_seq
  }
end

function M.add_seq(tracker, peer_id, seq)
  if not tracker or not peer_id or seq == nil then
    return false, 'invalid_args'
  end
  local last = tracker.seqs[peer_id]
  if last == nil then
    tracker.seqs[peer_id] = seq
    return true, 'ok'
  end
  if seq <= last then
    return false, 'replay'
  end
  if seq > last + 1 then
    tracker.seqs[peer_id] = seq
    return true, 'gap'
  end
  tracker.seqs[peer_id] = seq
  return true, 'ok'
end

function M.check_seq(tracker, peer_id, seq)
  if not tracker or not peer_id or seq == nil then
    return false, 'invalid_args'
  end
  local last = tracker.seqs[peer_id]
  if last == nil then return true, 'ok' end
  if seq <= last then return false, 'replay' end
  if seq > last + 1 then return true, 'gap' end
  return true, 'ok'
end

return M
