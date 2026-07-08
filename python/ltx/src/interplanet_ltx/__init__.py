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
PLAN_CONFIRM 10 min
"""

from ._models import LtxNode, LtxSegmentSpec, LtxPlan, LtxSegment, LtxNodeUrl

from ._core import (
    VERSION,
    SEG_TYPES,
    DEFAULT_QUANTUM,
    DEFAULT_SEGMENTS,
    upgrade_config,
    upgrade_plan_to_v3,
    create_plan,
    compute_segments,
    compute_segments_for,
    pair_delay,
    total_min,
    make_plan_id,
    encode_hash,
    decode_hash,
    build_node_urls,
    delay_from_planets,
)

from ._conference import build_conference_agenda, prime_time_report

from ._ics import generate_ics

from ._formatting import format_hms, format_utc

from ._rest import store_session, get_session, download_ics, submit_feedback

from ._security import (
    canonical_json, generate_nik, nik_fingerprint, is_nik_expired,
    sign_plan, verify_plan,
    SequenceTracker, add_seq, check_seq,
    GlobalSequenceTracker, check_issued_at, ISSUED_AT_MAX_AGE_DAYS,
)

from ._cbor import CborTag, encode_cbor, decode_cbor

from ._cose import (
    COSE_SIGN1_TAG, COSE_ALG_ED25519,
    sign_plan_cose, verify_plan_cose, verify_plan_any,
)

from ._merkle import MerkleLog, verify_tree_head

from ._keydist import (
    create_key_bundle,
    verify_and_cache_keys,
    create_revocation,
    apply_revocation,
)

from ._bib import (
    add_bib, verify_bib, generate_bib_key,
    add_bib_ed25519, verify_bib_ed25519,
)
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

from ._session import (
    DELAY_VIOLATION_WARN_S,
    DELAY_VIOLATION_DEGRADE_S,
    LOCK_TIMEOUT_FACTOR,
    create_session,
    transition,
    lock_timeout_ms,
)

from ._amend import (
    plan_hash,
    create_amendment,
    verify_amendment_chain,
    insert_buffer_via_amendment,
)

from ._registers import (
    create_register_entry,
    verify_register_entry,
    order_entries,
    reduce_questions,
    reduce_actions,
    emit_question_seeds,
)

from ._merge import (
    merge_logs,
    entries_root,
    run_merge_segment,
    recover_partition,
)

__version__ = VERSION

__all__ = [
    # Models
    'LtxNode', 'LtxSegmentSpec', 'LtxPlan', 'LtxSegment', 'LtxNodeUrl',
    # Constants
    'VERSION', 'SEG_TYPES', 'DEFAULT_QUANTUM', 'DEFAULT_SEGMENTS',
    # Core
    'upgrade_config', 'upgrade_plan_to_v3', 'create_plan', 'compute_segments',
    'compute_segments_for', 'pair_delay', 'total_min',
    'make_plan_id', 'encode_hash', 'decode_hash', 'build_node_urls',
    'delay_from_planets',
    # Conference mode (Epic 71)
    'build_conference_agenda', 'prime_time_report',
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
    # Global freshness scope (Story 70.5)
    'GlobalSequenceTracker', 'check_issued_at', 'ISSUED_AT_MAX_AGE_DAYS',
    # Deterministic CBOR (Story 70.5)
    'CborTag', 'encode_cbor', 'decode_cbor',
    # COSE_Sign1 (Story 70.5)
    'COSE_SIGN1_TAG', 'COSE_ALG_ED25519',
    'sign_plan_cose', 'verify_plan_cose', 'verify_plan_any',
    # Merkle Audit Log
    'MerkleLog', 'verify_tree_head',
    # Key Distribution
    'create_key_bundle', 'verify_and_cache_keys', 'create_revocation', 'apply_revocation',
    # BPSec BIB
    'add_bib', 'verify_bib', 'generate_bib_key',
    'add_bib_ed25519', 'verify_bib_ed25519',
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
    # Session State Machine (Epic 68)
    'DELAY_VIOLATION_WARN_S', 'DELAY_VIOLATION_DEGRADE_S', 'LOCK_TIMEOUT_FACTOR',
    'create_session', 'transition', 'lock_timeout_ms',
    # Plan Amendments (Epic 68.3)
    'plan_hash', 'create_amendment', 'verify_amendment_chain',
    'insert_buffer_via_amendment',
    # Registers (Epic 69)
    'create_register_entry', 'verify_register_entry', 'order_entries',
    'reduce_questions', 'reduce_actions', 'emit_question_seeds',
    # Merge + partition recovery (Epic 69)
    'merge_logs', 'entries_root', 'run_merge_segment', 'recover_partition',
]
