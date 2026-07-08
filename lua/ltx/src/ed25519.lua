-- ed25519.lua -- Pure-Lua Ed25519 signature verification (LTX v1.1, Epic 72)
--
-- Faithful port of the TweetNaCl crypto_sign_open verification path
-- (public domain), plus SHA-512. Lua 5.4+ (64-bit integers, bitwise ops).
--
-- Only VERIFICATION is provided: the LTX v1.1 conformance vectors carry
-- real Ed25519 signatures, and verify is the cross-port requirement
-- (LTX-SECURITY.md §7). Signing still requires a native crypto library.

local M = {}

--------------- SHA-512 --------------------------------------------------------

local SHA512_K = {
  0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
  0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
  0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
  0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
  0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
  0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
  0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
  0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
  0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
  0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
  0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
  0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
  0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
  0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
  0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
  0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
  0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
  0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
  0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
  0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
}

local function rotr64(x, n)
  return (x >> n) | (x << (64 - n))
end

--- SHA-512 digest of a byte string. Returns 64 raw bytes.
function M.sha512(msg)
  local H = {
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
  }
  local len = #msg
  local padlen = (111 - len) % 128
  local padded = msg .. '\128' .. string.rep('\0', padlen)
    .. string.pack('>i8', 0) .. string.pack('>i8', len * 8)

  local W = {}
  for blk = 0, #padded // 128 - 1 do
    local base = blk * 128 + 1
    for i = 1, 16 do
      W[i] = string.unpack('>i8', padded, base + (i - 1) * 8)
    end
    for i = 17, 80 do
      local w15, w2 = W[i - 15], W[i - 2]
      local s0 = rotr64(w15, 1) ~ rotr64(w15, 8) ~ (w15 >> 7)
      local s1 = rotr64(w2, 19) ~ rotr64(w2, 61) ~ (w2 >> 6)
      W[i] = W[i - 16] + s0 + W[i - 7] + s1
    end
    local a, b, c, d, e, f, g, h =
      H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 1, 80 do
      local S1 = rotr64(e, 14) ~ rotr64(e, 18) ~ rotr64(e, 41)
      local ch = (e & f) ~ ((~e) & g)
      local t1 = h + S1 + ch + SHA512_K[i] + W[i]
      local S0 = rotr64(a, 28) ~ rotr64(a, 34) ~ rotr64(a, 39)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = S0 + maj
      h = g; g = f; f = e; e = d + t1
      d = c; c = b; b = a; a = t1 + t2
    end
    H[1] = H[1] + a; H[2] = H[2] + b; H[3] = H[3] + c; H[4] = H[4] + d
    H[5] = H[5] + e; H[6] = H[6] + f; H[7] = H[7] + g; H[8] = H[8] + h
  end

  local out = {}
  for i = 1, 8 do
    out[i] = string.pack('>i8', H[i])
  end
  return table.concat(out)
end

--------------- GF(2^255-19) field arithmetic (16 x 16-bit limbs) --------------

local function gf(init)
  local r = {}
  for i = 1, 16 do
    r[i] = init and init[i] or 0
  end
  return r
end

local GF0 = gf()
local GF1 = gf({1})
local D  = gf({0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
               0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203})
local D2 = gf({0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
               0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406})
local BX = gf({0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
               0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169})
local BY = gf({0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
               0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666})
local SQRTM1 = gf({0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43,
                   0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83})

local function set25519(r, a)
  for i = 1, 16 do r[i] = a[i] end
end

local function car25519(o)
  for i = 1, 16 do
    o[i] = o[i] + 65536
    local c = o[i] // 65536  -- arithmetic shift right 16
    if i < 16 then
      o[i + 1] = o[i + 1] + c - 1
    else
      o[1] = o[1] + 38 * (c - 1)
    end
    o[i] = o[i] - c * 65536
  end
end

local function sel25519(p, q, b)
  local c = b == 1 and -1 or 0  -- ~(b-1) as all-ones/all-zeros mask
  for i = 1, 16 do
    local t = c & (p[i] ~ q[i])
    p[i] = p[i] ~ t
    q[i] = q[i] ~ t
  end
end

local function pack25519(n)
  local t = gf(n)
  car25519(t); car25519(t); car25519(t)
  local m = gf()
  for _ = 1, 2 do
    m[1] = t[1] - 0xffed
    for i = 2, 15 do
      m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1)
      m[i - 1] = m[i - 1] & 0xffff
    end
    m[16] = t[16] - 0x7fff - ((m[15] >> 16) & 1)
    local b = (m[16] >> 16) & 1
    m[15] = m[15] & 0xffff
    sel25519(t, m, 1 - b)
  end
  local out = {}
  for i = 1, 16 do
    out[2 * i - 1] = string.char(t[i] & 0xff)
    out[2 * i] = string.char((t[i] >> 8) & 0xff)
  end
  return table.concat(out)
end

local function neq25519(a, b)
  return pack25519(a) ~= pack25519(b)
end

local function par25519(a)
  local d = pack25519(a)
  return string.byte(d, 1) & 1
end

local function unpack25519(o, n)
  for i = 1, 16 do
    o[i] = string.byte(n, 2 * i - 1) + (string.byte(n, 2 * i) << 8)
  end
  o[16] = o[16] & 0x7fff
end

local function fadd(o, a, b)  -- A
  for i = 1, 16 do o[i] = a[i] + b[i] end
end

local function fsub(o, a, b)  -- Z
  for i = 1, 16 do o[i] = a[i] - b[i] end
end

local function fmul(o, a, b)  -- M
  local t = {}
  for i = 1, 31 do t[i] = 0 end
  for i = 1, 16 do
    local ai = a[i]
    for j = 1, 16 do
      t[i + j - 1] = t[i + j - 1] + ai * b[j]
    end
  end
  for i = 1, 15 do
    t[i] = t[i] + 38 * t[i + 16]
  end
  for i = 1, 16 do o[i] = t[i] end
  car25519(o); car25519(o)
end

local function fsquare(o, a)  -- S
  fmul(o, a, a)
end

local function inv25519(o, i)
  local c = gf(i)
  for a = 253, 0, -1 do
    fsquare(c, c)
    if a ~= 2 and a ~= 4 then fmul(c, c, i) end
  end
  set25519(o, c)
end

local function pow2523(o, i)
  local c = gf(i)
  for a = 250, 0, -1 do
    fsquare(c, c)
    if a ~= 1 then fmul(c, c, i) end
  end
  set25519(o, c)
end

--------------- Edwards-curve point operations ---------------------------------

-- Points are {X, Y, Z, T} in extended coordinates.

local function point_add(p, q)
  local a, b, c, d, t, e, f, g, h =
    gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf()
  fsub(a, p[2], p[1])
  fsub(t, q[2], q[1])
  fmul(a, a, t)
  fadd(b, p[1], p[2])
  fadd(t, q[1], q[2])
  fmul(b, b, t)
  fmul(c, p[4], q[4])
  fmul(c, c, D2)
  fmul(d, p[3], q[3])
  fadd(d, d, d)
  fsub(e, b, a)
  fsub(f, d, c)
  fadd(g, d, c)
  fadd(h, b, a)
  fmul(p[1], e, f)
  fmul(p[2], h, g)
  fmul(p[3], g, f)
  fmul(p[4], e, h)
end

local function cswap(p, q, b)
  for i = 1, 4 do
    sel25519(p[i], q[i], b)
  end
end

local function point_pack(p)
  local zi, tx, ty = gf(), gf(), gf()
  inv25519(zi, p[3])
  fmul(tx, p[1], zi)
  fmul(ty, p[2], zi)
  local r = pack25519(ty)
  local last = string.byte(r, 32) ~ (par25519(tx) << 7)
  return string.sub(r, 1, 31) .. string.char(last)
end

--- Scalar multiplication: p = s * q. s is a 32-byte little-endian string.
local function scalarmult(p, q, s)
  p[1] = gf(GF0); p[2] = gf(GF1); p[3] = gf(GF1); p[4] = gf(GF0)
  for i = 255, 0, -1 do
    local b = (string.byte(s, i // 8 + 1) >> (i & 7)) & 1
    cswap(p, q, b)
    point_add(q, p)
    point_add(p, p)
    cswap(p, q, b)
  end
end

local function scalarbase(p, s)
  local q = { gf(BX), gf(BY), gf(GF1), gf() }
  fmul(q[4], BX, BY)
  scalarmult(p, q, s)
end

--- Decompress a public key into the NEGATED point -A (TweetNaCl unpackneg).
-- Returns the point table, or nil if the key is not on the curve.
local function unpackneg(pk)
  local r = { gf(), gf(), gf(GF1), gf() }
  local t, chk, num, den, den2, den4, den6 =
    gf(), gf(), gf(), gf(), gf(), gf(), gf()
  unpack25519(r[2], pk)
  fsquare(num, r[2])
  fmul(den, num, D)
  fsub(num, num, r[3])
  fadd(den, r[3], den)

  fsquare(den2, den)
  fsquare(den4, den2)
  fmul(den6, den4, den2)
  fmul(t, den6, num)
  fmul(t, t, den)

  pow2523(t, t)
  fmul(t, t, num)
  fmul(t, t, den)
  fmul(t, t, den)
  fmul(r[1], t, den)

  fsquare(chk, r[1])
  fmul(chk, chk, den)
  if neq25519(chk, num) then fmul(r[1], r[1], SQRTM1) end

  fsquare(chk, r[1])
  fmul(chk, chk, den)
  if neq25519(chk, num) then return nil end

  if par25519(r[1]) == (string.byte(pk, 32) >> 7) then
    fsub(r[1], GF0, r[1])
  end

  fmul(r[4], r[1], r[2])
  return r
end

--------------- Scalar reduction mod L ------------------------------------------

local L = {
  237, 211, 245, 92, 26, 99, 18, 88, 214, 156, 247, 162, 222, 249, 222, 20,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16,
}

-- x: array of 64 integers (1-based). Returns 32-byte string x mod L.
local function modL(x)
  for i = 64, 33, -1 do
    local carry = 0
    local xi = x[i]
    for j = i - 32, i - 13 do
      x[j] = x[j] + carry - 16 * xi * L[j - (i - 32) + 1]
      carry = (x[j] + 128) // 256
      x[j] = x[j] - carry * 256
    end
    x[i - 12] = x[i - 12] + carry
    x[i] = 0
  end
  local carry = 0
  local top = x[32] // 16
  for j = 1, 32 do
    x[j] = x[j] + carry - top * L[j]
    carry = x[j] // 256
    x[j] = x[j] & 255
  end
  for j = 1, 32 do
    x[j] = x[j] - carry * L[j]
  end
  local out = {}
  for i = 1, 32 do
    if i < 32 then
      x[i + 1] = x[i + 1] + (x[i] // 256)
    end
    out[i] = string.char(x[i] & 255)
  end
  return table.concat(out)
end

-- Reduce a 64-byte digest string mod L → 32-byte scalar string.
local function reduce(h)
  local x = {}
  for i = 1, 64 do
    x[i] = string.byte(h, i)
  end
  return modL(x)
end

--------------- Verification ----------------------------------------------------

--- Verify an Ed25519 signature.
-- @param msg string  message bytes
-- @param sig string  64-byte signature (R || s)
-- @param pk  string  32-byte public key
-- @return boolean
function M.verify(msg, sig, pk)
  if type(msg) ~= 'string' or type(sig) ~= 'string' or type(pk) ~= 'string' then
    return false
  end
  if #sig ~= 64 or #pk ~= 32 then
    return false
  end
  local q = unpackneg(pk)
  if not q then
    return false
  end
  local h = reduce(M.sha512(string.sub(sig, 1, 32) .. pk .. msg))
  local p = { gf(), gf(), gf(), gf() }
  scalarmult(p, q, h)          -- p = h * (-A)
  local sb = { gf(), gf(), gf(), gf() }
  scalarbase(sb, string.sub(sig, 33, 64))  -- sb = s * B
  point_add(p, sb)             -- p = s*B - h*A
  return point_pack(p) == string.sub(sig, 1, 32)
end

return M
