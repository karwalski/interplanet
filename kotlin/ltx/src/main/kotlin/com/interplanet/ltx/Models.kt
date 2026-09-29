package com.interplanet.ltx

data class LtxNode(
    val id: String,
    val name: String,
    val role: String,
    val delay: Int = 0,
    val location: String = "earth"
)

/**
 * A segment in a plan's segment list. [speaker] (a node id) and [label] (an
 * agenda title) are the optional attribution fields of LTX-SPECIFICATION.md
 * section 3.4.1; null means absent, and absent fields are not serialised.
 */
data class LtxSegmentTemplate(
    val type: String,
    val q: Int = 1,
    val speaker: String? = null,
    val label: String? = null
)

data class LtxSegment(
    val segType: String,
    val nodeId: String,
    val startMs: Long,
    val endMs: Long,
    val durationMs: Long
)

data class LtxNodeUrl(
    val nodeId: String,
    val name: String,
    val role: String,
    val url: String
)

data class LtxPlan(
    val v: Int = 2,
    val title: String,
    val start: String,
    val quantum: Int = 5,
    val mode: String = "LTX",
    val nodes: List<LtxNode>,
    val segments: List<LtxSegmentTemplate>
)
