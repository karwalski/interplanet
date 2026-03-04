"""
interplanet_ltx — LTX (Light-Time eXchange) Python SDK
Story 22.2 — Python wrapper for the LTX protocol

Mirrors the JavaScript LTX SDK (js/ltx-sdk.js) and optionally integrates
with the interplanet_time library (story 18.1) for planet-based delay lookup.

Quick start
-----------
>>> from interplanet_ltx import create_plan, compute_segments, generate_ics
>>> plan = create_plan(host_name='Earth HQ', remote_name='Mars Hab-01', delay=800)
>>> segs = compute_segments(plan)
>>> print(segs[0].type, segs[0].dur_min, 'min')
PLAN_CONFIRM 6 min
"""

from ._models import LtxNode, LtxSegmentSpec, LtxPlan, LtxSegment, LtxNodeUrl

from ._core import (
    VERSION,
    SEG_TYPES,
    DEFAULT_QUANTUM,
    DEFAULT_SEGMENTS,
    upgrade_config,
    create_plan,
    compute_segments,
    total_min,
    make_plan_id,
    encode_hash,
    decode_hash,
    build_node_urls,
    delay_from_planets,
)

from ._ics import generate_ics

from ._formatting import format_hms, format_utc

from ._rest import store_session, get_session, download_ics, submit_feedback

from ._security import (
    canonical_json, generate_nik, nik_fingerprint, is_nik_expired,
    sign_plan, verify_plan,
    SequenceTracker, add_seq, check_seq,
)

from ._merkle import MerkleLog, verify_tree_head

from ._keydist import (
    create_key_bundle,
    verify_and_cache_keys,
    create_revocation,
    apply_revocation,
)

from ._bib import add_bib, verify_bib, generate_bib_key
from ._bcb import generate_session_key, encrypt_window, decrypt_window

from ._eok import (
    create_eok,
    create_emergency_override,
    verify_emergency_override,
    create_co_sig,
    check_multi_auth,
)

from ._manifest import (
    artefact_sha256,
    create_window_manifest,
    verify_window_manifest,
    hedged_sign,
    hedged_verify,
)

from ._conjunction import (
    PostConjunctionQueue,
    create_conjunction_checkpoint,
    verify_conjunction_checkpoint,
    create_post_conjunction_queue,
    create_post_conjunction_clear,
    verify_post_conjunction_clear,
)

__version__ = VERSION

__all__ = [
    # Models
    'LtxNode', 'LtxSegmentSpec', 'LtxPlan', 'LtxSegment', 'LtxNodeUrl',
    # Constants
    'VERSION', 'SEG_TYPES', 'DEFAULT_QUANTUM', 'DEFAULT_SEGMENTS',
    # Core
    'upgrade_config', 'create_plan', 'compute_segments', 'total_min',
    'make_plan_id', 'encode_hash', 'decode_hash', 'build_node_urls',
    'delay_from_planets',
    # ICS
    'generate_ics',
    # Formatting
    'format_hms', 'format_utc',
    # REST
    'store_session', 'get_session', 'download_ics', 'submit_feedback',
    # Security
    'canonical_json', 'generate_nik', 'nik_fingerprint', 'is_nik_expired',
    'sign_plan', 'verify_plan',
    # Sequence tracking
    'SequenceTracker', 'add_seq', 'check_seq',
    # Merkle Audit Log
    'MerkleLog', 'verify_tree_head',
    # Key Distribution
    'create_key_bundle', 'verify_and_cache_keys', 'create_revocation', 'apply_revocation',
    # BPSec BIB
    'add_bib', 'verify_bib', 'generate_bib_key',
    # BPSec BCB
    'generate_session_key', 'encrypt_window', 'decrypt_window',
    # EOK / MULTI-AUTH
    'create_eok', 'create_emergency_override', 'verify_emergency_override',
    'create_co_sig', 'check_multi_auth',
    # Window Manifests
    'artefact_sha256', 'create_window_manifest', 'verify_window_manifest',
    'hedged_sign', 'hedged_verify',
    # Conjunction Checkpoints
    'PostConjunctionQueue',
    'create_conjunction_checkpoint', 'verify_conjunction_checkpoint',
    'create_post_conjunction_queue',
    'create_post_conjunction_clear', 'verify_post_conjunction_clear',
]
