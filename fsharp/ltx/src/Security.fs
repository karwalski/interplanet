// Security.fs --- Epic 29 security cascade for InterplanetLtx (F#)
// Stories 29.1, 29.4, 29.5
// Real Ed25519 signatures via NSec.Cryptography (libsodium); SHA-256 via
// System.Security.Cryptography.
//
// This file is consumed via #load from .fsx scripts, and a #load-ed .fs file
// cannot declare a nuget reference itself. Every consuming script must put
// the reference BEFORE the #load line:
//   #r "nuget: NSec.Cryptography, 24.4.0"
//   #load "../src/Security.fs"

module InterplanetLtx.Security

open System
open System.Text
open System.Security.Cryptography
open System.Collections.Generic

// ---- base64url helpers ----

let b64uEncode (data: byte[]) : string =
    Convert.ToBase64String(data)
        .Replace('+', '-').Replace('/', '_').TrimEnd('=')

let b64uDecode (s: string) : byte[] =
    let mutable t = s.Replace('-', '+').Replace('_', '/')
    let m = t.Length % 4
    if m = 2 then t <- t + "=="
    elif m = 3 then t <- t + "="
    Convert.FromBase64String(t)

// ---- canonical JSON ----

let rec canonicalJson (v: obj) : string =
    match v with
    | null            -> "null"
    | :? bool as b    -> if b then "true" else "false"
    | :? int as n     -> string n
    | :? int64 as n   -> string n
    | :? float as f   -> if f = Math.Floor(f) then string (int64 f) else string f
    | :? string as s  -> jsonStr s
    | :? (obj seq) as arr ->
        "[" + String.concat "," (Seq.map canonicalJson arr) + "]"
    | :? (obj[]) as arr ->
        "[" + String.concat "," (Array.map canonicalJson arr) + "]"
    | :? IDictionary<string,obj> as m ->
        let sorted = m |> Seq.sortBy (fun kv -> kv.Key)
        let parts  = sorted |> Seq.map (fun kv -> jsonStr kv.Key + ":" + canonicalJson kv.Value)
        "{" + String.concat "," parts + "}"
    | _               -> jsonStr (string v)

/// JSON.stringify string quoting: quote, backslash and control characters
/// escaped (\b \f \n \r \t, others as \u00xx); everything else raw.
and jsonStr (s: string) : string =
    let sb = StringBuilder("\"")
    let mutable i = 0
    while i < s.Length do
        let c = s.[i]
        match c with
        | '"'  -> sb.Append("\\\"") |> ignore
        | '\\' -> sb.Append("\\\\") |> ignore
        | '\b' -> sb.Append("\\b")  |> ignore
        | '\012' -> sb.Append("\\f")  |> ignore
        | '\n' -> sb.Append("\\n")  |> ignore
        | '\r' -> sb.Append("\\r")  |> ignore
        | '\t' -> sb.Append("\\t")  |> ignore
        | c when c < ' ' -> sb.Append("\\u").Append((int c).ToString("x4")) |> ignore
        | c when Char.IsHighSurrogate c && i + 1 < s.Length && Char.IsLowSurrogate s.[i + 1] ->
            sb.Append(c).Append(s.[i + 1]) |> ignore
            i <- i + 1
        // ES2019 well-formed JSON.stringify: lone surrogates as \uXXXX.
        | c when Char.IsSurrogate c -> sb.Append("\\u").Append((int c).ToString("x4")) |> ignore
        | c    -> sb.Append(c) |> ignore
        i <- i + 1
    sb.Append('"') |> ignore
    sb.ToString()

/// Decode the raw text of a JSON string token (quotes included), keeping
/// lone surrogates (JSON.parse accepts "\ud800"; JsonElement.GetString throws).
let unquoteJson (raw: string) : string =
    let sb = StringBuilder(raw.Length)
    let mutable i = 1
    while i < raw.Length - 1 do
        let c = raw.[i]
        if c <> '\\' then sb.Append(c) |> ignore
        else
            i <- i + 1
            match raw.[i] with
            | 'b' -> sb.Append('\b') |> ignore
            | 'f' -> sb.Append('\f') |> ignore
            | 'n' -> sb.Append('\n') |> ignore
            | 'r' -> sb.Append('\r') |> ignore
            | 't' -> sb.Append('\t') |> ignore
            | 'u' ->
                sb.Append(char (Convert.ToInt32(raw.Substring(i + 1, 4), 16))) |> ignore
                i <- i + 4
            | n -> sb.Append(n) |> ignore
        i <- i + 1
    sb.ToString()

/// JavaScript \s: ECMAScript WhiteSpace and LineTerminator. (Char.IsWhiteSpace
/// differs: it includes U+0085 and not U+FEFF.)
let isJsSpace (c: char) : bool =
    match c with
    | '\t' | '\n' | '\v' | '\f' | '\r' | ' ' | '\u00a0' | '\u1680' | '\u2028' | '\u2029'
    | '\u202f' | '\u205f' | '\u3000' | '\ufeff' -> true
    | c -> c >= '\u2000' && c <= '\u200a'

/// s.replace(/\s+/g, '').toUpperCase() as in ltx-sdk.js makePlanId.
/// (ToUpperInvariant has no special casing: Upper.jsToUpper does JS toUpperCase.)
let stripJsSpaceUpper (s: string) : string =
    Upper.jsToUpper (String(s.ToCharArray() |> Array.filter (isJsSpace >> not)))

// ---- SHA-256 helper ----

let sha256 (data: byte[]) : byte[] =
    use h = SHA256.Create()
    h.ComputeHash(data)

// ---- Ed25519 (NSec) ----

let private ed = NSec.Cryptography.SignatureAlgorithm.Ed25519

/// Import a raw 32-byte Ed25519 seed as an NSec signing key.
let private importSeedKey (privRaw: byte[]) : NSec.Cryptography.Key =
    NSec.Cryptography.Key.Import(
        ed, ReadOnlySpan<byte>(privRaw),
        NSec.Cryptography.KeyBlobFormat.RawPrivateKey)

/// Ed25519 signature of `data` with a raw 32-byte seed (NSec/libsodium).
let signBytes (data: byte[]) (privRaw: byte[]) : byte[] =
    use key = importSeedKey privRaw
    ed.Sign(key, ReadOnlySpan<byte>(data))

// ---- NIK type ----

type Nik =
    { KeyType:        string
      NodeId:         string
      Kid:            string
      IssuedAt:       string
      ExpiresAt:      string
      NodeLabel:      string
      PublicKeyB64:   string
      PrivateKeyB64:  string
      PubRaw:         byte[]
      PrivRaw:        byte[] }

// ---- ISO-8601 UTC ----

let private isoNow (offsetDays: int) : string =
    DateTimeOffset.UtcNow.AddDays(float offsetDays)
        .ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

// ---- generate_nik ----

/// Cross-port key formats (LTX-SECURITY):
///   privateKey = base64url of the raw 32-byte Ed25519 seed
///   publicKey  = base64url of the raw 32-byte Ed25519 public key
///   nodeId     = base64url of the first 16 bytes of SHA-256(raw public key)
let private mkNik (pubRaw: byte[]) (privRaw: byte[]) (validDays: int) (nodeLabel: string) : Nik =
    let h      = sha256 pubRaw
    let nodeId = b64uEncode h.[..15]
    { KeyType        = "ltx-nik-v1"
      NodeId         = nodeId
      Kid            = nodeId
      IssuedAt       = isoNow 0
      ExpiresAt      = isoNow validDays
      NodeLabel      = nodeLabel
      PublicKeyB64   = b64uEncode pubRaw
      PrivateKeyB64  = b64uEncode privRaw
      PubRaw         = pubRaw
      PrivRaw        = privRaw }

let generateNik (validDays: int) (nodeLabel: string) : Nik =
    // An Ed25519 private key is any random 32-byte seed (RFC 8032).
    let privRaw = Array.zeroCreate<byte> 32
    use rng = RandomNumberGenerator.Create()
    rng.GetBytes(privRaw)
    use key = importSeedKey privRaw
    let pubRaw = key.PublicKey.Export(NSec.Cryptography.KeyBlobFormat.RawPublicKey)
    mkNik pubRaw privRaw validDays nodeLabel

/// Rebuild a NIK from a base64url-encoded raw 32-byte Ed25519 seed
/// (the cross-port private-key format).
let nikFromSeed (seedB64: string) (validDays: int) (nodeLabel: string) : Nik =
    let privRaw = b64uDecode seedB64
    use key = importSeedKey privRaw
    let pubRaw = key.PublicKey.Export(NSec.Cryptography.KeyBlobFormat.RawPublicKey)
    mkNik pubRaw privRaw validDays nodeLabel

// ---- is_nik_expired ----

let isNikExpired (nik: Nik) : bool =
    nik.ExpiresAt <= isoNow 0

// ---- COSE_Sign1 types ----

type CoseSign1 =
    { ProtectedHdr: string
      Kid:          string
      Payload:      string
      Signature:    string }

type SignedPlan =
    { Plan:       IDictionary<string,obj>
      CoseSign1:  CoseSign1 }

// ---- sign_plan ----

let signPlan (plan: IDictionary<string,obj>) (nik: Nik) : SignedPlan =
    let protectedJson = canonicalJson (dict [("alg", -19 :> obj)] :> IDictionary<string,obj>)
    let protectedB64  = b64uEncode (Encoding.UTF8.GetBytes protectedJson)
    let payloadJson   = canonicalJson plan
    let payloadB64    = b64uEncode (Encoding.UTF8.GetBytes payloadJson)
    let sigStructJson = canonicalJson ([| "Signature1" :> obj; protectedB64; ""; payloadB64 |])
    let sigStructBytes = Encoding.UTF8.GetBytes sigStructJson
    // Real Ed25519 signature over the COSE-style sig structure (NSec/libsodium).
    use key = importSeedKey nik.PrivRaw
    let sigBytes = ed.Sign(key, ReadOnlySpan<byte>(sigStructBytes))
    { Plan      = plan
      CoseSign1 = { ProtectedHdr = protectedB64
                    Kid          = nik.Kid
                    Payload      = payloadB64
                    Signature    = b64uEncode sigBytes } }

// ---- verify_plan ----

let verifyPlan (sp: SignedPlan) (keyCache: IDictionary<string, Nik>) : bool * string =
    let cs  = sp.CoseSign1
    let kid = cs.Kid
    match keyCache.TryGetValue(kid) with
    | false, _ -> false, "key_not_in_cache"
    | true, nik ->
        if isNikExpired nik then false, "key_expired"
        else
            let expectedPayload = b64uEncode (Encoding.UTF8.GetBytes (canonicalJson sp.Plan))
            if cs.Payload <> expectedPayload then false, "payload_mismatch"
            else
                let sigStructJson  = canonicalJson ([| "Signature1" :> obj; cs.ProtectedHdr; ""; cs.Payload |])
                let sigStructBytes = Encoding.UTF8.GetBytes sigStructJson
                // Real Ed25519 verification against the cached NIK's public key.
                let valid =
                    try
                        let pub = NSec.Cryptography.PublicKey.Import(
                                    ed, ReadOnlySpan<byte>(b64uDecode nik.PublicKeyB64),
                                    NSec.Cryptography.KeyBlobFormat.RawPublicKey)
                        ed.Verify(pub, ReadOnlySpan<byte>(sigStructBytes),
                                  ReadOnlySpan<byte>(b64uDecode cs.Signature))
                    with _ -> false
                if valid then true, "ok" else false, "signature_mismatch"

// ---- SequenceTracker ----

type SequenceTracker(planId: string) =
    let seqs = Dictionary<string, int64>()

    member _.PlanId = planId

    member _.AddSeq(peerId: string, seq: int64) : bool * string =
        match seqs.TryGetValue(peerId) with
        | false, _ ->
            seqs.[peerId] <- seq
            true, "ok"
        | true, last ->
            if seq <= last then false, "replay"
            elif seq > last + 1L then
                seqs.[peerId] <- seq
                true, "gap"
            else
                seqs.[peerId] <- seq
                true, "ok"

    member _.CheckSeq(peerId: string, seq: int64) : bool * string =
        match seqs.TryGetValue(peerId) with
        | false, _ -> true, "ok"
        | true, last ->
            if seq <= last then false, "replay"
            elif seq > last + 1L then true, "gap"
            else true, "ok"
