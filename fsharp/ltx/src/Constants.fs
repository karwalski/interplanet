// Constants.fs --- SDK constants
// F# port of ltx-sdk.js (Story 33.14)

module InterplanetLtx.Constants

open InterplanetLtx.Models

let VERSION = "1.1.0"

let SEG_TYPES = [| "PLAN_CONFIRM"; "TX"; "RX"; "CAUCUS"; "OPEN"; "BUFFER" |]

let DEFAULT_QUANTUM = 5  // minutes per quantum (LTX-SPECIFICATION §3.2)

let DEFAULT_API_BASE = "https://api.interplanet.app/ltx"

let DEFAULT_SEGMENTS : LtxSegmentTemplate list = [
    segment "PLAN_CONFIRM" 2
    segment "TX" 2
    segment "RX" 2
    segment "CAUCUS" 2
    segment "TX" 2
    segment "RX" 2
    segment "BUFFER" 1
]

// Story 26.4 constants
let DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2
let DELAY_VIOLATION_WARN_S = 120
let DELAY_VIOLATION_DEGRADED_S = 300
let SESSION_STATES = [| "INIT"; "LOCKED"; "RUNNING"; "DEGRADED"; "COMPLETE" |]
