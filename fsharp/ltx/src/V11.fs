// V11.fs --- LTX v1.1 core subset (Epic 72, Story 72.3)
// F# port of the TypeScript reference (segments.ts / session.ts / amend.ts /
// registers.ts / cbor.ts / cose.ts).
//
// Real Ed25519 verification is provided by NSec.Cryptography (libsodium),
// the same backend Security.fs uses for the Epic-29 primitives. Load with:
//   #r "nuget: NSec.Cryptography, 24.4.0"
//   #load "Security.fs"
//   #load "V11.fs"

module InterplanetLtx.V11

open System
open System.Text
open System.Security.Cryptography
open System.Collections.Generic
open InterplanetLtx.Security

// ---- constants ----

let VERSION = "1.1.0"
let COSE_SIGN1_TAG = 18L
let COSE_ALG_ED25519 = -19L
let DELAY_VIOLATION_DEGRADE_S = 300L
let LOCK_TIMEOUT_FACTOR = 2L

// ---- v1.1 plan model ----

type NodeV11 = {
    id:       string
    name:     string
    role:     string
    delay:    int64
    location: string
}

type SegV11 = {
    segType: string
    q:       int
    speaker: string option
    label:   string option
}

type PlanV11 = {
    v:            int
    title:        string
    start:        string
    quantum:      int
    mode:         string
    nodes:        NodeV11 list
    segments:     SegV11 list
    delays:       Map<string, int64> option   // v3 pair matrix, "A|B" sorted ids
    planVersion:  int option
    prevPlanHash: string option
}

/// Generic dictionary projection for canonical JSON hashing.
let planToDict (p: PlanV11) : IDictionary<string, obj> =
    let d = Dictionary<string, obj>()
    d.["v"] <- box p.v
    d.["title"] <- box p.title
    d.["start"] <- box p.start
    d.["quantum"] <- box p.quantum
    d.["mode"] <- box p.mode
    let nodes = List<obj>()
    for n in p.nodes do
        let nd = Dictionary<string, obj>()
        nd.["id"] <- box n.id
        nd.["name"] <- box n.name
        nd.["role"] <- box n.role
        nd.["delay"] <- box n.delay
        nd.["location"] <- box n.location
        nodes.Add(box nd)
    d.["nodes"] <- box nodes
    let segs = List<obj>()
    for s in p.segments do
        let sd = Dictionary<string, obj>()
        sd.["type"] <- box s.segType
        sd.["q"] <- box s.q
        match s.speaker with Some sp -> sd.["speaker"] <- box sp | None -> ()
        match s.label with Some lb -> sd.["label"] <- box lb | None -> ()
        segs.Add(box sd)
    d.["segments"] <- box segs
    match p.delays with
    | Some delays ->
        let dd = Dictionary<string, obj>()
        for KeyValue(k, v) in delays do dd.[k] <- box v
        d.["delays"] <- box dd
    | None -> ()
    match p.planVersion with Some pv -> d.["planVersion"] <- box pv | None -> ()
    match p.prevPlanHash with Some ph -> d.["prevPlanHash"] <- box ph | None -> ()
    d :> IDictionary<string, obj>

/// SHA-256 hex of the RFC 8785 canonical JSON of a plan (amend.ts).
let planHash (p: PlanV11) : string =
    let bytes = sha256 (Encoding.UTF8.GetBytes(canonicalJson (planToDict p)))
    (bytes |> Array.map (sprintf "%02x") |> String.concat "")

// ---- FROZEN v2 JSON serialisation (insertion-order JSON.stringify) ----

let private jsonEsc (s: string) : string = jsonStr s

/// v,title,start,quantum,mode,nodes(id,name,role,delay,location),
/// segments(type,q[,speaker][,label]) — must stay byte-identical (§4.3).
let toJsonV2 (p: PlanV11) : string =
    let sb = StringBuilder()
    sb.Append('{') |> ignore
    sb.Append("\"v\":").Append(p.v) |> ignore
    sb.Append(",\"title\":").Append(jsonEsc p.title) |> ignore
    sb.Append(",\"start\":").Append(jsonEsc p.start) |> ignore
    sb.Append(",\"quantum\":").Append(p.quantum) |> ignore
    sb.Append(",\"mode\":").Append(jsonEsc p.mode) |> ignore
    sb.Append(",\"nodes\":[") |> ignore
    p.nodes |> List.iteri (fun i n ->
        if i > 0 then sb.Append(',') |> ignore
        sb.Append("{\"id\":").Append(jsonEsc n.id) |> ignore
        sb.Append(",\"name\":").Append(jsonEsc n.name) |> ignore
        sb.Append(",\"role\":").Append(jsonEsc n.role) |> ignore
        sb.Append(",\"delay\":").Append(n.delay) |> ignore
        sb.Append(",\"location\":").Append(jsonEsc n.location).Append('}') |> ignore)
    sb.Append("],\"segments\":[") |> ignore
    p.segments |> List.iteri (fun i s ->
        if i > 0 then sb.Append(',') |> ignore
        sb.Append("{\"type\":").Append(jsonEsc s.segType) |> ignore
        sb.Append(",\"q\":").Append(s.q) |> ignore
        match s.speaker with
        | Some sp -> sb.Append(",\"speaker\":").Append(jsonEsc sp) |> ignore
        | None -> ()
        match s.label with
        | Some lb -> sb.Append(",\"label\":").Append(jsonEsc lb) |> ignore
        | None -> ()
        sb.Append('}') |> ignore)
    sb.Append("]}") |> ignore
    sb.ToString()

// ---- 1. plan ID (v3 SHA-256 + frozen v2 polynomial) ----

let private stripWs (s: string) =
    String(s.ToCharArray() |> Array.filter (Char.IsWhiteSpace >> not))

/// Deterministic plan ID. v3: SHA-256 over RFC 8785 canonical JSON (§4.5,
/// "-v3-" infix). v2: FROZEN 32-bit polynomial hash over the JSON (§4.3).
let makePlanId (p: PlanV11) : string =
    let date = p.start.Substring(0, 10).Replace("-", "")
    let hostStr =
        let h = if p.nodes.IsEmpty then "HOST" else (stripWs p.nodes.Head.name).ToUpper()
        if h.Length > 8 then h.Substring(0, 8) else h
    let nodeStr =
        if p.nodes.Length > 1 then
            let s =
                p.nodes.Tail
                |> List.map (fun n ->
                    let x = (stripWs n.name).ToUpper()
                    if x.Length > 4 then x.Substring(0, 4) else x)
                |> String.concat "-"
            if s.Length > 16 then s.Substring(0, 16) else s
        else "RX"
    if p.v >= 3 then
        let digest = planHash p
        sprintf "LTX-%s-%s-%s-v3-%s" date hostStr nodeStr (digest.Substring(0, 8))
    else
        let raw = toJsonV2 p
        let mutable h = 0u
        for c in raw do h <- h * 31u + uint32 c
        sprintf "LTX-%s-%s-%s-v2-%08x" date hostStr nodeStr h

// ---- 1. pairDelay + computeSegmentsFor ----

/// One-way delay in seconds between two nodes (§3.7). v3 pair matrix is
/// authoritative where present; fallback: HOST pairs use the node's declared
/// delay, non-HOST pairs the sum of both HOST-relative delays.
let pairDelay (p: PlanV11) (nodeIdA: string) (nodeIdB: string) : int64 =
    if nodeIdA = nodeIdB then 0L
    else
        let key = [ nodeIdA; nodeIdB ] |> List.sortWith (fun a b -> String.CompareOrdinal(a, b)) |> String.concat "|"
        match p.delays |> Option.bind (Map.tryFind key) with
        | Some d -> d
        | None ->
            let a = p.nodes |> List.tryFind (fun n -> n.id = nodeIdA)
            let b = p.nodes |> List.tryFind (fun n -> n.id = nodeIdB)
            match a, b with
            | None, _ -> failwithf "pairDelay: unknown node %s" nodeIdA
            | _, None -> failwithf "pairDelay: unknown node %s" nodeIdB
            | Some a, Some b ->
                let hostId = p.nodes.Head.id
                if nodeIdA = hostId then b.delay
                elif nodeIdB = hostId then a.delay
                else a.delay + b.delay

type ViewerSegmentV11 = {
    segType:        string
    q:              int
    startMs:        int64
    endMs:          int64
    durMin:         int
    speaker:        string option
    label:          string option
    perspective:    string   // "transmit" | "receive" | "neutral"
    arrivalOffsetS: int64
}

let private parseIsoMs (iso: string) : int64 =
    DateTimeOffset.Parse(iso, Globalization.CultureInfo.InvariantCulture,
        Globalization.DateTimeStyles.AssumeUniversal).ToUnixTimeMilliseconds()

/// Base timed segments (epoch ms) for a v1.1 plan.
let computeSegmentsV11 (p: PlanV11) : ViewerSegmentV11 list =
    let qMs = int64 p.quantum * 60000L
    let mutable t = parseIsoMs p.start
    [ for s in p.segments do
        let durMs = int64 s.q * qMs
        yield { segType = s.segType; q = s.q; startMs = t; endMs = t + durMs
                durMin = s.q * p.quantum; speaker = s.speaker; label = s.label
                perspective = "neutral"; arrivalOffsetS = 0L }
        t <- t + durMs ]

/// Timed segments from viewer V's perspective (§14.3): a segment attributed to
/// speaker S starts for V at segStart + pairDelay(S, V).
let computeSegmentsFor (p: PlanV11) (viewerNodeId: string) : ViewerSegmentV11 list =
    if not (p.nodes |> List.exists (fun n -> n.id = viewerNodeId)) then
        failwithf "computeSegmentsFor: unknown viewer %s" viewerNodeId
    computeSegmentsV11 p
    |> List.mapi (fun i seg ->
        let tpl = p.segments.[i]
        match tpl.speaker with
        | None -> { seg with perspective = "neutral"; arrivalOffsetS = 0L }
        | Some _ when tpl.segType <> "TX" && tpl.segType <> "SPEAK" ->
            { seg with perspective = "neutral"; arrivalOffsetS = 0L }
        | Some sp when sp = viewerNodeId ->
            { seg with perspective = "transmit"; arrivalOffsetS = 0L }
        | Some sp ->
            let shiftS = pairDelay p sp viewerNodeId
            { seg with
                startMs = seg.startMs + shiftS * 1000L
                endMs = seg.endMs + shiftS * 1000L
                perspective = "receive"
                arrivalOffsetS = shiftS })

// ---- Ed25519 (NSec) helpers ----

type NikV11 = {
    nodeId:       string
    publicKeyB64: string
    validUntil:   string
}

let private ed = NSec.Cryptography.SignatureAlgorithm.Ed25519

let verifyBytes (data: byte[]) (sigB64: string) (nik: NikV11) : bool =
    try
        let pub = NSec.Cryptography.PublicKey.Import(
                    ed, ReadOnlySpan<byte>(b64uDecode nik.publicKeyB64),
                    NSec.Cryptography.KeyBlobFormat.RawPublicKey)
        ed.Verify(pub, ReadOnlySpan<byte>(data), ReadOnlySpan<byte>(b64uDecode sigB64))
    with _ -> false

let private isExpiredV11 (nik: NikV11) : bool =
    try
        DateTimeOffset.UtcNow > DateTimeOffset.Parse(nik.validUntil,
            Globalization.CultureInfo.InvariantCulture,
            Globalization.DateTimeStyles.AssumeUniversal)
    with _ -> false

let private lookupKid (kid: string) (keyCache: IDictionary<string, NikV11>) : NikV11 option =
    match keyCache.TryGetValue(kid) with
    | true, nik -> Some nik
    | _ -> keyCache.Values |> Seq.tryFind (fun n -> n.nodeId.StartsWith(kid))

// ---- TRANSITIONAL JSON COSE_Sign1 envelope (LTX-SECURITY §7.2) ----

type CoseSign1V11 = {
    protectedHdr: string
    kid:          string
    payload:      string
    signature:    string
}

type SignedPlanV11 = {
    plan:      PlanV11
    coseSign1: CoseSign1V11
}

/// Verify the JSON COSE_Sign1 plan envelope: Ed25519 over
/// canonicalJSON(["Signature1", protected, "", payload]).
let verifyPlanEnvelope (sp: SignedPlanV11) (keyCache: IDictionary<string, NikV11>) : bool * string =
    match lookupKid sp.coseSign1.kid keyCache with
    | None -> false, "key_not_in_cache"
    | Some nik ->
        if isExpiredV11 nik then false, "key_expired"
        else
            let sigStruct =
                canonicalJson [| box "Signature1"; box sp.coseSign1.protectedHdr
                                 box ""; box sp.coseSign1.payload |]
            if not (verifyBytes (Encoding.UTF8.GetBytes sigStruct) sp.coseSign1.signature nik) then
                false, "signature_invalid"
            else
                let payloadStr = Encoding.UTF8.GetString(b64uDecode sp.coseSign1.payload)
                if payloadStr <> canonicalJson (planToDict sp.plan) then
                    false, "payload_mismatch"
                else true, "ok"

// ---- 3. amendment chains (amend.ts) ----

/// Verify an amendment chain: chain[0] is the root, each later element a
/// successive amendment (LTX-SECURITY.md §7.6). Checks per link: signature,
/// planVersion +1 steps, prevPlanHash equality with the recomputed predecessor
/// hash; the root must carry no prevPlanHash.
let verifyAmendmentChain (chain: SignedPlanV11 list) (keyCache: IDictionary<string, NikV11>) : bool * string =
    if chain.IsEmpty then false, "empty_chain"
    else
        let sigFailure =
            chain |> List.mapi (fun i link -> i, verifyPlanEnvelope link keyCache)
                  |> List.tryFind (fun (_, (ok, _)) -> not ok)
        match sigFailure with
        | Some (i, (_, reason)) -> false, sprintf "link_%d_%s" i reason
        | None ->
            if chain.Head.plan.prevPlanHash.IsSome then false, "root_has_prev_hash"
            else
                let rec walk (prevPlan: PlanV11) (prevVersion: int) i =
                    if i >= chain.Length then true, "ok"
                    else
                        let p = chain.[i].plan
                        if p.v <> 3 then false, sprintf "link_%d_not_v3" i
                        elif (defaultArg p.planVersion 0) <> prevVersion + 1 then
                            false, sprintf "link_%d_version_gap" i
                        elif p.prevPlanHash <> Some (planHash prevPlan) then
                            false, sprintf "link_%d_prev_hash_mismatch" i
                        else walk p (defaultArg p.planVersion 0) (i + 1)
                walk chain.Head.plan (defaultArg chain.Head.plan.planVersion 1) 1

// ---- 4. register entries + reducers (registers.ts) ----

type RegisterEntryV11 = {
    entryId:   string
    sessionId: string
    nodeId:    string
    seq:       int
    entryType: string
    content:   IDictionary<string, obj>
    timestamp: string
    entrySig:  string
}

let private entryDict (e: RegisterEntryV11) (includeSig: bool) : IDictionary<string, obj> =
    let d = Dictionary<string, obj>()
    d.["entryId"] <- box e.entryId
    d.["sessionId"] <- box e.sessionId
    d.["nodeId"] <- box e.nodeId
    d.["seq"] <- box e.seq
    d.["type"] <- box e.entryType
    d.["content"] <- box e.content
    d.["timestamp"] <- box e.timestamp
    if includeSig then d.["sig"] <- box e.entrySig
    d :> IDictionary<string, obj>

/// Verify a register entry signature (Ed25519 over canonical JSON sans sig).
let verifyRegisterEntry (e: RegisterEntryV11) (keyCache: IDictionary<string, NikV11>) : bool * string =
    if String.IsNullOrEmpty e.entrySig then false, "missing_sig"
    else
        match keyCache.TryGetValue(e.nodeId) with
        | false, _ -> false, "key_not_in_cache"
        | true, nik ->
            let canon = canonicalJson (entryDict e false)
            if verifyBytes (Encoding.UTF8.GetBytes canon) e.entrySig nik then true, "ok"
            else false, "signature_invalid"

/// Total order (timestamp, nodeId, seq) — §8.2.
let compareEntries (a: RegisterEntryV11) (b: RegisterEntryV11) : int =
    let c = String.CompareOrdinal(a.timestamp, b.timestamp)
    if c <> 0 then c
    else
        let c2 = String.CompareOrdinal(a.nodeId, b.nodeId)
        if c2 <> 0 then c2 else compare a.seq b.seq

/// De-duplicate by (nodeId, seq) and sort into the §8.2 total order.
let orderEntries (entries: RegisterEntryV11 list) : RegisterEntryV11 list =
    let seen = Dictionary<string, RegisterEntryV11>()
    for e in entries do
        let key = sprintf "%s %d" e.nodeId e.seq
        if not (seen.ContainsKey key) then seen.[key] <- e
    seen.Values |> List.ofSeq |> List.sortWith compareEntries

type QuestionStateV11 = {
    qid:            string
    text:           string
    submitter:      string
    urgency:        string option
    intendedWindow: string option
    status:         string   // OPEN | ANSWERED | WITHDRAWN
    response:       string option
    responder:      string option
    version:        int
}

type ActionStateV11 = {
    aid:          string
    description:  string
    owner:        string option
    dueTimeUTC:   string option
    originWindow: string option
    status:       string   // PROPOSED | ACCEPTED | REJECTED | DONE
    version:      int
}

let private tryStr (d: IDictionary<string, obj>) (key: string) : string option =
    match d.TryGetValue key with
    | true, v when not (isNull v) -> Some (string v)
    | _ -> None

let private tryInt (d: IDictionary<string, obj>) (key: string) (fallback: int) : int =
    match d.TryGetValue key with
    | true, (:? int as i) -> i
    | true, (:? int64 as l) -> int l
    | true, (:? string as s) -> (match Int32.TryParse s with | true, i -> i | _ -> fallback)
    | _ -> fallback

/// §8.2 conflict rule: higher version wins; tie -> lowest editor nodeId.
let private wins (inV: int) (inEd: string) (curV: int) (curEd: string) : bool =
    if inV <> curV then inV > curV else String.CompareOrdinal(inEd, curEd) < 0

/// Reduce question register state from log entries (§9.4).
let reduceQuestions (entries: RegisterEntryV11 list) : Map<string, QuestionStateV11> * string list =
    let byId = Dictionary<string, QuestionStateV11>()
    let winners = Dictionary<string, int * string * string>()
    let superseded = List<string>()
    for e in orderEntries entries do
        if e.entryType = "question" then
            let qid = e.entryId
            if byId.ContainsKey qid then superseded.Add e.entryId
            else
                winners.[qid] <- (1, e.nodeId, e.entryId)
                byId.[qid] <-
                    { qid = qid
                      text = defaultArg (tryStr e.content "text") ""
                      submitter = e.nodeId
                      urgency = tryStr e.content "urgency"
                      intendedWindow = tryStr e.content "intendedWindow"
                      status = "OPEN"; response = None; responder = None; version = 1 }
        elif e.entryType = "question_response" then
            let qid = defaultArg (tryStr e.content "qid") ""
            match byId.TryGetValue qid with
            | false, _ -> superseded.Add e.entryId
            | true, q ->
                let version = tryInt e.content "version" (q.version + 1)
                let proceed =
                    match winners.TryGetValue qid with
                    | true, (curV, curEd, curId) ->
                        if not (wins version e.nodeId curV curEd) then
                            superseded.Add e.entryId; false
                        else
                            (if curId <> q.qid then superseded.Add curId); true
                    | _ -> true
                if proceed then
                    winners.[qid] <- (version, e.nodeId, e.entryId)
                    let status =
                        if tryStr e.content "status" = Some "WITHDRAWN" then "WITHDRAWN"
                        else "ANSWERED"
                    byId.[qid] <-
                        { q with
                            status = status
                            response = (match tryStr e.content "response" with Some r -> Some r | None -> q.response)
                            responder = Some e.nodeId
                            version = version }
    (byId |> Seq.map (fun kv -> kv.Key, kv.Value) |> Map.ofSeq), List.ofSeq superseded

let private ACTION_STATUSES = set [ "PROPOSED"; "ACCEPTED"; "REJECTED"; "DONE" ]

/// Reduce action register state from log entries (§10.2).
let reduceActions (entries: RegisterEntryV11 list) : Map<string, ActionStateV11> * string list =
    let byId = Dictionary<string, ActionStateV11>()
    let winners = Dictionary<string, int * string * string>()
    let superseded = List<string>()
    for e in orderEntries entries do
        if e.entryType = "action" then
            let aid = e.entryId
            if byId.ContainsKey aid then superseded.Add e.entryId
            else
                winners.[aid] <- (1, e.nodeId, e.entryId)
                byId.[aid] <-
                    { aid = aid
                      description = defaultArg (tryStr e.content "description") ""
                      owner = tryStr e.content "owner"
                      dueTimeUTC = tryStr e.content "dueTimeUTC"
                      originWindow = tryStr e.content "originWindow"
                      status = "PROPOSED"; version = 1 }
        elif e.entryType = "action_update" then
            let aid = defaultArg (tryStr e.content "aid") ""
            match byId.TryGetValue aid with
            | false, _ -> superseded.Add e.entryId
            | true, a ->
                let version = tryInt e.content "version" (a.version + 1)
                let proceed =
                    match winners.TryGetValue aid with
                    | true, (curV, curEd, curId) ->
                        if not (wins version e.nodeId curV curEd) then
                            superseded.Add e.entryId; false
                        else
                            (if curId <> a.aid then superseded.Add curId); true
                    | _ -> true
                if proceed then
                    winners.[aid] <- (version, e.nodeId, e.entryId)
                    let status =
                        match tryStr e.content "status" with
                        | Some s when ACTION_STATUSES.Contains s -> s
                        | _ -> a.status
                    byId.[aid] <-
                        { a with
                            status = status
                            description = defaultArg (tryStr e.content "description") a.description
                            owner = (match tryStr e.content "owner" with Some o -> Some o | None -> a.owner)
                            dueTimeUTC = (match tryStr e.content "dueTimeUTC" with Some d -> Some d | None -> a.dueTimeUTC)
                            version = version }
    (byId |> Seq.map (fun kv -> kv.Key, kv.Value) |> Map.ofSeq), List.ofSeq superseded

// ---- Merkle root over ordered entries (merkle.ts / merge.ts) ----

let private leafHash (entryBytes: byte[]) : byte[] =
    sha256 (Array.append [| 0x00uy |] entryBytes)

let private nodeHash (left: byte[]) (right: byte[]) : byte[] =
    sha256 (Array.concat [ [| 0x01uy |]; left; right ])

let rec private rootOf (leaves: byte[][]) : byte[] =
    if leaves.Length = 0 then Array.zeroCreate 32
    elif leaves.Length = 1 then leaves.[0]
    else
        let mid = pown 2 (int (floor (Math.Log2 (float (leaves.Length - 1)))))
        nodeHash (rootOf leaves.[.. mid - 1]) (rootOf leaves.[mid ..])

/// RFC 9162-style Merkle root (hex) over an ordered entry list.
/// Leaf: SHA-256(0x00 || canonicalJSON(entry)); node: SHA-256(0x01 || L || R).
let entriesRoot (entries: RegisterEntryV11 list) : string =
    let leaves =
        entries
        |> List.map (fun e -> leafHash (Encoding.UTF8.GetBytes(canonicalJson (entryDict e true))))
        |> Array.ofList
    rootOf leaves |> Array.map (sprintf "%02x") |> String.concat ""

// ---- 5. CBOR decode (RFC 8949 deterministic subset, cbor.ts) ----

type CborValue =
    | CInt of int64
    | CBytes of byte[]
    | CText of string
    | CArray of CborValue list
    | CMap of (CborValue * CborValue) list
    | CTag of int64 * CborValue
    | CBool of bool
    | CNull

exception CborError of string

let private readHead (buf: byte[]) (pos: byref<int>) : int * int64 =
    if pos >= buf.Length then raise (CborError "truncated")
    let initial = buf.[pos]
    pos <- pos + 1
    let major = int initial >>> 5
    let info = int initial &&& 0x1f
    if info < 24 then major, int64 info
    elif info = 24 then
        if pos >= buf.Length then raise (CborError "truncated")
        let v = int64 buf.[pos] in pos <- pos + 1; major, v
    elif info = 25 then
        if pos + 2 > buf.Length then raise (CborError "truncated")
        let v = (int64 buf.[pos] <<< 8) ||| int64 buf.[pos + 1]
        pos <- pos + 2; major, v
    elif info = 26 then
        if pos + 4 > buf.Length then raise (CborError "truncated")
        let v = (int64 buf.[pos] <<< 24) ||| (int64 buf.[pos + 1] <<< 16)
                ||| (int64 buf.[pos + 2] <<< 8) ||| int64 buf.[pos + 3]
        pos <- pos + 4; major, v
    elif info = 27 then
        if pos + 8 > buf.Length then raise (CborError "truncated")
        let mutable v = 0UL
        for i in 0 .. 7 do v <- (v <<< 8) ||| uint64 buf.[pos + i]
        pos <- pos + 8
        if v > uint64 Int64.MaxValue then raise (CborError "integer too large")
        major, int64 v
    else raise (CborError "indefinite lengths not supported")

let rec private decodeItem (buf: byte[]) (pos: byref<int>) : CborValue =
    if pos >= buf.Length then raise (CborError "truncated")
    match buf.[pos] with
    | 0xf6uy -> pos <- pos + 1; CNull
    | 0xf5uy -> pos <- pos + 1; CBool true
    | 0xf4uy -> pos <- pos + 1; CBool false
    | _ ->
        let major, arg = readHead buf &pos
        match major with
        | 0 -> CInt arg
        | 1 -> CInt (-arg - 1L)
        | 2 ->
            let n = int arg
            if pos + n > buf.Length then raise (CborError "truncated bstr")
            let bytes = buf.[pos .. pos + n - 1]
            pos <- pos + n
            CBytes bytes
        | 3 ->
            let n = int arg
            if pos + n > buf.Length then raise (CborError "truncated tstr")
            let s = Encoding.UTF8.GetString(buf, pos, n)
            pos <- pos + n
            CText s
        | 4 ->
            let items = List<CborValue>()
            for _ in 1L .. arg do items.Add(decodeItem buf &pos)
            CArray (List.ofSeq items)
        | 5 ->
            let items = List<CborValue * CborValue>()
            for _ in 1L .. arg do
                let k = decodeItem buf &pos
                let v = decodeItem buf &pos
                items.Add(k, v)
            CMap (List.ofSeq items)
        | 6 -> CTag (arg, decodeItem buf &pos)
        | _ -> raise (CborError (sprintf "unsupported major type %d / simple value" major))

/// Decode deterministic CBOR bytes (ints, bstr, tstr, array, map, tag,
/// bool/null). Rejects floats, indefinite lengths, and trailing bytes.
let decodeCbor (bytes: byte[]) : CborValue =
    let mutable pos = 0
    let v = decodeItem bytes &pos
    if pos <> bytes.Length then raise (CborError "trailing bytes")
    v

// ---- 5. COSE_Sign1 verification (RFC 9052, cose.ts) ----

let private encodeCborHead (major: int) (arg: int) : byte[] =
    if arg < 24 then [| byte ((major <<< 5) ||| arg) |]
    elif arg < 0x100 then [| byte ((major <<< 5) ||| 24); byte arg |]
    elif arg < 0x10000 then [| byte ((major <<< 5) ||| 25); byte (arg >>> 8); byte arg |]
    else [| byte ((major <<< 5) ||| 26); byte (arg >>> 24); byte (arg >>> 16); byte (arg >>> 8); byte arg |]

/// Sig_structure = CBOR ["Signature1", protected, h'', payload].
let private sigStructureBytes (protectedBytes: byte[]) (payload: byte[]) : byte[] =
    Array.concat [
        encodeCborHead 4 4
        encodeCborHead 3 10
        Encoding.UTF8.GetBytes "Signature1"
        encodeCborHead 2 protectedBytes.Length
        protectedBytes
        encodeCborHead 2 0
        encodeCborHead 2 payload.Length
        payload
    ]

/// Verify a CBOR COSE_Sign1 plan envelope (tag 18) against the key cache.
/// Rejects non-Ed25519 algorithms (protected {1: -19} required) and payloads
/// that do not match the plan's canonical JSON.
let verifyPlanCose (plan: PlanV11 option) (coseSign1CborB64: string)
                   (keyCache: IDictionary<string, NikV11>) : bool * string =
    if String.IsNullOrEmpty coseSign1CborB64 then false, "missing_cose_sign1"
    else
        let decoded =
            try Some (decodeCbor (b64uDecode coseSign1CborB64))
            with _ -> None
        match decoded with
        | None -> false, "cbor_decode_failed"
        | Some (CTag (tag, CArray [ CBytes protectedBytes; unprotected; CBytes payload; CBytes signature ]))
            when tag = COSE_SIGN1_TAG ->
            let protectedMap =
                try
                    match decodeCbor protectedBytes with
                    | CMap m -> Some m
                    | _ -> None
                with _ -> None
            match protectedMap with
            | None -> false, "protected_decode_failed"
            | Some m when not (m |> List.exists (fun (k, v) -> k = CInt 1L && v = CInt COSE_ALG_ED25519)) ->
                false, "unsupported_alg"
            | Some _ ->
                let kid =
                    match unprotected with
                    | CMap um ->
                        um |> List.tryPick (fun (k, v) ->
                            match k, v with
                            | CInt 4L, CBytes kb -> Some (b64uEncode kb)
                            | CInt 4L, CText ks -> Some ks
                            | _ -> None)
                    | _ -> None
                match kid with
                | None -> false, "missing_kid"
                | Some kid ->
                    match lookupKid kid keyCache with
                    | None -> false, "key_not_in_cache"
                    | Some nik when isExpiredV11 nik -> false, "key_expired"
                    | Some nik ->
                        let sigStruct = sigStructureBytes protectedBytes payload
                        if not (verifyBytes sigStruct (b64uEncode signature) nik) then
                            false, "signature_invalid"
                        else
                            match plan with
                            | Some p when Encoding.UTF8.GetString payload <> canonicalJson (planToDict p) ->
                                false, "payload_mismatch"
                            | _ -> true, "ok"
        | Some (CTag _) -> false, "malformed_cose_sign1"
        | Some _ -> false, "not_cose_sign1"

// ---- 2. session state machine (session.ts) ----

type QuorumSpec =
    | All
    | Majority
    | Count of int

type SessionEventV11 =
    | StartLock of nowMs: int64
    | PlanConfirm of nowMs: int64 * nodeId: string * planId: string
    | Tick of nowMs: int64
    | SessionStart of nowMs: int64
    | DelayMeasured of nowMs: int64 * nodeId: string * measuredDelayS: int64
    | EokOverride of nowMs: int64 * verified: bool
    | AmendmentProposed of nowMs: int64 * planId: string * planVersion: int * affectedNodeIds: string list
    | AmendmentConfirmed of nowMs: int64 * nodeId: string * planId: string
    | HostDecision of nowMs: int64 * decision: string
    | SessionEnd of nowMs: int64

type PendingAmendmentV11 = {
    planId:          string
    planVersion:     int
    affectedNodeIds: string list
    confirmed:       string list
    proposedAtMs:    int64
    timeoutMs:       int64
}

type SessionCtxV11 = {
    state:             string
    plan:              PlanV11
    planId:            string
    sessionRootPlanId: string
    planVersion:       int
    lock:              string option   // "FULL" | "QUORUM"
    lockStartedAtMs:   int64 option
    lockTimeoutMs:     int64
    confirmations:     Map<string, string>
    mismatched:        string list
    quorumThreshold:   int
    subset:            string list option
    degradedReasons:   string list
    resumeState:       string option
    pendingAmendment:  PendingAmendmentV11 option
}

let private participants (p: PlanV11) = p.nodes |> List.filter (fun n -> n.role = "PARTICIPANT")

/// 2 × one-way delay to the furthest node, in ms (§5.1).
let lockTimeoutMs (p: PlanV11) : int64 =
    let maxDelayS = p.nodes |> List.fold (fun m n -> max m n.delay) 0L
    LOCK_TIMEOUT_FACTOR * maxDelayS * 1000L

let private quorumCount (p: PlanV11) (quorum: QuorumSpec) : int =
    let total = (participants p).Length
    match quorum with
    | Majority -> total / 2 + 1
    | Count n -> min (max n 1) total
    | All -> total

/// Create a session context in DRAFT state (§5).
let createSession (plan: PlanV11) (planId: string) (quorum: QuorumSpec) : SessionCtxV11 =
    { state = "DRAFT"; plan = plan; planId = planId; sessionRootPlanId = planId
      planVersion = defaultArg plan.planVersion 1
      lock = None; lockStartedAtMs = None; lockTimeoutMs = lockTimeoutMs plan
      confirmations = Map.empty; mismatched = []
      quorumThreshold = quorumCount plan quorum
      subset = None; degradedReasons = []; resumeState = None; pendingAmendment = None }

let private fullLockReached (ctx: SessionCtxV11) : bool =
    participants ctx.plan
    |> List.forall (fun n -> ctx.confirmations.TryFind n.id = Some ctx.planId)

let private quorumReached (ctx: SessionCtxV11) : bool =
    (participants ctx.plan
     |> List.filter (fun n -> ctx.confirmations.TryFind n.id = Some ctx.planId)
     |> List.length) >= ctx.quorumThreshold

/// Ascending-delay fallback ordering over confirmed participants (§5.3).
let private confirmedSubset (ctx: SessionCtxV11) : string list =
    let host = ctx.plan.nodes.Head
    let confirmed =
        participants ctx.plan
        |> List.filter (fun n -> ctx.confirmations.TryFind n.id = Some ctx.planId)
        |> List.sortBy (fun n -> n.delay)
        |> List.map (fun n -> n.id)
    host.id :: confirmed

/// Declared one-way delay: v3 pair matrix HOST row, else node.delay.
let private declaredDelayS (p: PlanV11) (nodeId: string) : int64 option =
    p.nodes |> List.tryFind (fun n -> n.id = nodeId)
    |> Option.map (fun node ->
        match p.delays with
        | Some delays ->
            let hostId = p.nodes.Head.id
            let key = [ hostId; nodeId ] |> List.sortWith (fun a b -> String.CompareOrdinal(a, b)) |> String.concat "|"
            match delays.TryFind key with Some d -> d | None -> node.delay
        | None -> node.delay)

let private degrade (ctx: SessionCtxV11) (reason: string) : SessionCtxV11 =
    let next = { ctx with degradedReasons = ctx.degradedReasons @ [ reason ] }
    if ctx.state = "DEGRADED" then next else { next with state = "DEGRADED" }

/// Advance the session state machine. Pure: same (ctx, event) always yields the
/// same result. Side-effects of the reference implementation are simplified
/// away — the state/lock sequence matches the reference exactly.
let transition (ctx: SessionCtxV11) (ev: SessionEventV11) : SessionCtxV11 =
    match ev with
    | StartLock nowMs ->
        if ctx.state <> "DRAFT" then ctx
        else
            let hostId = ctx.plan.nodes.Head.id
            { ctx with
                state = "LOCKING"
                lockStartedAtMs = Some nowMs
                confirmations = ctx.confirmations.Add(hostId, ctx.planId) }

    | PlanConfirm (_, nodeId, planId) ->
        if ctx.state <> "LOCKING" && ctx.state <> "DEGRADED" then ctx
        else
            let next = { ctx with confirmations = ctx.confirmations.Add(nodeId, planId) }
            if planId <> ctx.planId then
                { next with mismatched = (next.mismatched |> List.filter ((<>) nodeId)) @ [ nodeId ] }
            else
                let next = { next with mismatched = next.mismatched |> List.filter ((<>) nodeId) }
                if fullLockReached next then
                    // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
                    { next with state = "LOCKED"; lock = Some "FULL"; subset = None }
                else next

    | Tick nowMs ->
        match ctx.state, ctx.lockStartedAtMs with
        | "LOCKING", Some startedAt when nowMs - startedAt >= ctx.lockTimeoutMs ->
            // Lock timeout expired (§5.1).
            if quorumReached ctx then
                let subset = confirmedSubset ctx
                degrade { ctx with lock = Some "QUORUM"; subset = Some subset }
                        (sprintf "quorum lock with subset [%s]" (String.concat "," subset))
            else degrade ctx "plan-lock timeout without quorum"
        | _ -> ctx

    | SessionStart _ ->
        if ctx.state = "LOCKED" then { ctx with state = "ACTIVE" } else ctx

    | DelayMeasured (_, nodeId, measuredDelayS) ->
        if ctx.state <> "ACTIVE" && ctx.state <> "LOCKED" && ctx.state <> "DEGRADED" then ctx
        else
            match declaredDelayS ctx.plan nodeId with
            | None -> ctx
            | Some declared ->
                if abs (measuredDelayS - declared) > DELAY_VIOLATION_DEGRADE_S then
                    degrade ctx (sprintf "delay violation %s: measured %ds vs declared %ds"
                                     nodeId (int measuredDelayS) (int declared))
                else ctx

    | EokOverride (_, verified) ->
        if ctx.state = "COMPLETE" || ctx.state = "ABORTED" then ctx
        elif not verified then ctx
        elif ctx.state = "EMERGENCY_HOLD" then ctx
        else { ctx with state = "EMERGENCY_HOLD"; resumeState = Some ctx.state }

    | AmendmentProposed (nowMs, planId, planVersion, affectedNodeIds) ->
        if ctx.state <> "ACTIVE" && ctx.state <> "LOCKED" && ctx.state <> "DEGRADED" then ctx
        elif planVersion <> ctx.planVersion + 1 then ctx
        else
            // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
            let maxDelayS =
                ctx.plan.nodes
                |> List.filter (fun n -> List.contains n.id affectedNodeIds)
                |> List.fold (fun m n -> max m n.delay) 0L
            { ctx with
                pendingAmendment = Some {
                    planId = planId; planVersion = planVersion
                    affectedNodeIds = affectedNodeIds; confirmed = []
                    proposedAtMs = nowMs
                    timeoutMs = LOCK_TIMEOUT_FACTOR * maxDelayS * 1000L } }

    | AmendmentConfirmed (_, nodeId, planId) ->
        match ctx.pendingAmendment with
        | Some pa when planId = pa.planId && List.contains nodeId pa.affectedNodeIds ->
            let confirmed = (pa.confirmed |> List.filter ((<>) nodeId)) @ [ nodeId ]
            if confirmed.Length < pa.affectedNodeIds.Length then
                { ctx with pendingAmendment = Some { pa with confirmed = confirmed } }
            else
                // All affected nodes confirmed — the amendment applies.
                { ctx with planId = pa.planId; planVersion = pa.planVersion; pendingAmendment = None }
        | _ -> ctx

    | HostDecision (_, decision) ->
        match decision with
        | "abort" when ctx.state <> "COMPLETE" && ctx.state <> "ABORTED" ->
            { ctx with state = "ABORTED" }
        | "resume" when ctx.state = "EMERGENCY_HOLD" ->
            { ctx with state = defaultArg ctx.resumeState "ACTIVE"; resumeState = None }
        | "continue" when ctx.state = "DEGRADED" ->
            { ctx with state = "ACTIVE" }  // §5.2: HOST continues with subset.
        | _ -> ctx

    | SessionEnd _ ->
        if ctx.state = "ACTIVE" || ctx.state = "DEGRADED" then { ctx with state = "COMPLETE" }
        else ctx
