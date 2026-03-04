"""Data models for the LTX Python SDK."""

from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class LtxNode:
    id: str
    name: str
    role: str               # 'HOST' | 'PARTICIPANT'
    delay: float = 0.0      # one-way signal delay in seconds
    location: str = 'earth'


@dataclass
class LtxSegmentSpec:
    type: str   # 'PLAN_CONFIRM' | 'TX' | 'RX' | 'CAUCUS' | 'BUFFER' | 'MERGE'
    q: int      # number of quanta


@dataclass
class LtxPlan:
    v: int
    title: str
    start: str              # ISO 8601 UTC
    quantum: int            # minutes per quantum
    mode: str
    segments: List[LtxSegmentSpec]
    nodes: List[LtxNode]


@dataclass
class LtxSegment:
    type: str
    q: int
    start: str              # ISO 8601
    end: str                # ISO 8601
    dur_min: int


@dataclass
class LtxNodeUrl:
    node_id: str
    name: str
    role: str
    url: str
