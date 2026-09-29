// Models.fs --- LTX data model record types
// F# port of ltx-sdk.js (Story 33.14)

module InterplanetLtx.Models

type LtxNode = {
    id:       string
    name:     string
    role:     string
    delay:    int
    location: string
}

/// A segment in a plan's segment list. speaker (a node id) and label (an
/// agenda title) are the optional attribution fields of LTX-SPECIFICATION.md
/// section 3.4.1; None means absent, and absent fields are not serialised.
type LtxSegmentTemplate = {
    segType: string
    q:       int
    speaker: string option
    label:   string option
}

/// An unattributed segment template (no speaker, no label).
let segment (segType: string) (q: int) : LtxSegmentTemplate =
    { segType = segType; q = q; speaker = None; label = None }

type LtxSegment = {
    segType:    string
    q:          int
    durationMs: int
    startMs:    int64
    endMs:      int64
}

type LtxNodeUrl = {
    nodeId:   string
    nodeName: string
    url:      string
}

type LtxPlan = {
    v:        int
    title:    string
    start:    string
    quantum:  int
    mode:     string
    nodes:    LtxNode list
    segments: LtxSegmentTemplate list
    planId:   string option
}
