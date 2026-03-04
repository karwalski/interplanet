// Constants.fs --- SDK constants
// F# port of ltx-sdk.js (Story 33.14)

module InterplanetLtx.Constants

open InterplanetLtx.Models

let VERSION = "1.0.0"

let SEG_TYPES = [| "PLAN_CONFIRM"; "TX"; "RX"; "CAUCUS"; "OPEN"; "BUFFER" |]

let DEFAULT_QUANTUM = 3  // minutes per quantum

let DEFAULT_API_BASE = "https://api.interplanet.app/ltx"

let DEFAULT_SEGMENTS : LtxSegmentTemplate list = [
    { segType = "PLAN_CONFIRM"; q = 2 }
    { segType = "TX";           q = 2 }
    { segType = "RX";           q = 2 }
    { segType = "CAUCUS";       q = 2 }
    { segType = "TX";           q = 2 }
    { segType = "RX";           q = 2 }
    { segType = "BUFFER";       q = 1 }
]

// Story 26.4 constants
let DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2
let DELAY_VIOLATION_WARN_S = 120
let DELAY_VIOLATION_DEGRADED_S = 300
let SESSION_STATES = [| "INIT"; "LOCKED"; "RUNNING"; "DEGRADED"; "COMPLETE" |]
