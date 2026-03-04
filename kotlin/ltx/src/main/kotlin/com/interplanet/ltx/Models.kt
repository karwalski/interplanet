package com.interplanet.ltx

data class LtxNode(
    val id: String,
    val name: String,
    val role: String,
    val delay: Int = 0,
    val location: String = "earth"
)

data class LtxSegmentTemplate(
    val type: String,
    val q: Int = 1
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
    val mode: String = "async",
    val nodes: List<LtxNode>,
    val segments: List<LtxSegmentTemplate>
)
