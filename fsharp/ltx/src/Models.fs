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

type LtxSegmentTemplate = {
    segType: string
    q:       int
}

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
