"""test_ltx.py — unit tests for the interplanet_ltx Python SDK.
Story 22.2 · stdlib unittest · no external dependencies.
"""

import json
import sys
import os
import unittest

# Allow running without pip install
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import interplanet_ltx as ltx
from interplanet_ltx import (
    LtxPlan, LtxNode, LtxSegmentSpec,
    create_plan, upgrade_config, compute_segments, total_min,
    make_plan_id, encode_hash, decode_hash, build_node_urls,
    generate_ics, format_hms, format_utc,
    DEFAULT_QUANTUM, DEFAULT_SEGMENTS, SEG_TYPES, VERSION,
)


class TestConstants(unittest.TestCase):

    def test_version_string(self):
        self.assertRegex(VERSION, r'^\d+\.\d+\.\d+$')

    def test_seg_types_count(self):
        self.assertEqual(len(SEG_TYPES), 6)
        self.assertIn('TX', SEG_TYPES)
        self.assertIn('RX', SEG_TYPES)
        self.assertIn('PLAN_CONFIRM', SEG_TYPES)
        self.assertIn('CAUCUS', SEG_TYPES)
        self.assertIn('BUFFER', SEG_TYPES)
        self.assertIn('MERGE', SEG_TYPES)

    def test_default_quantum(self):
        # LTX-SPECIFICATION.md §3.2: default quantum is 5 (bug B12 fix)
        self.assertEqual(DEFAULT_QUANTUM, 5)

    def test_default_segments_count(self):
        self.assertEqual(len(DEFAULT_SEGMENTS), 7)

    def test_default_segments_types(self):
        types = [s['type'] for s in DEFAULT_SEGMENTS]
        self.assertIn('PLAN_CONFIRM', types)
        self.assertIn('TX', types)
        self.assertIn('RX', types)
        self.assertIn('BUFFER', types)


class TestCreatePlan(unittest.TestCase):

    def setUp(self):
        self.plan = create_plan(
            title='Test Session',
            start='2026-01-01T12:00:00Z',
            delay=800,
        )

    def test_returns_ltx_plan(self):
        self.assertIsInstance(self.plan, LtxPlan)

    def test_v2(self):
        self.assertEqual(self.plan.v, 2)

    def test_title(self):
        self.assertEqual(self.plan.title, 'Test Session')

    def test_start(self):
        self.assertEqual(self.plan.start, '2026-01-01T12:00:00Z')

    def test_quantum(self):
        self.assertEqual(self.plan.quantum, DEFAULT_QUANTUM)

    def test_mode(self):
        self.assertEqual(self.plan.mode, 'LTX')

    def test_two_nodes(self):
        self.assertEqual(len(self.plan.nodes), 2)

    def test_host_node(self):
        n0 = self.plan.nodes[0]
        self.assertEqual(n0.role, 'HOST')
        self.assertEqual(n0.delay, 0.0)
        self.assertEqual(n0.location, 'earth')

    def test_participant_delay(self):
        n1 = self.plan.nodes[1]
        self.assertEqual(n1.delay, 800)
        self.assertEqual(n1.role, 'PARTICIPANT')

    def test_seven_segments(self):
        self.assertEqual(len(self.plan.segments), 7)

    def test_custom_host_name(self):
        p = create_plan(host_name='London Office', start='2026-01-01T12:00:00Z')
        self.assertEqual(p.nodes[0].name, 'London Office')

    def test_custom_quantum(self):
        p = create_plan(quantum=5, start='2026-01-01T12:00:00Z')
        self.assertEqual(p.quantum, 5)

    def test_default_start_is_future(self):
        from datetime import datetime, timezone
        p = create_plan()
        from datetime import datetime, timezone
        start_dt = datetime.fromisoformat(p.start.replace('Z', '+00:00'))
        self.assertGreater(start_dt, datetime.now(timezone.utc))

    def test_custom_segments(self):
        segs = [{'type': 'TX', 'q': 4}, {'type': 'RX', 'q': 4}]
        p = create_plan(segments=segs, start='2026-01-01T12:00:00Z')
        self.assertEqual(len(p.segments), 2)
        self.assertEqual(p.segments[0].type, 'TX')


class TestUpgradeConfig(unittest.TestCase):

    def test_v1_to_v2(self):
        v1 = {'txName': 'Mission Control', 'rxName': 'Mars Base', 'delay': 600}
        v2 = upgrade_config(v1)
        self.assertEqual(v2['v'], 2)
        self.assertIn('nodes', v2)
        self.assertEqual(len(v2['nodes']), 2)
        self.assertEqual(v2['nodes'][0]['name'], 'Mission Control')
        self.assertEqual(v2['nodes'][1]['name'], 'Mars Base')
        self.assertEqual(v2['nodes'][1]['delay'], 600)

    def test_v2_unchanged(self):
        plan = create_plan(start='2026-01-01T12:00:00Z')
        from interplanet_ltx._core import _plan_as_dict
        d = _plan_as_dict(plan)
        out = upgrade_config(d)
        self.assertEqual(out['nodes'], d['nodes'])

    def test_mars_remote_location(self):
        v1 = {'txName': 'Earth', 'rxName': 'Mars Hab', 'delay': 0}
        v2 = upgrade_config(v1)
        self.assertEqual(v2['nodes'][1]['location'], 'mars')

    def test_moon_remote_location(self):
        v1 = {'txName': 'Earth', 'rxName': 'Moon Base', 'delay': 0}
        v2 = upgrade_config(v1)
        self.assertEqual(v2['nodes'][1]['location'], 'moon')

    def test_earth_fallback_location(self):
        v1 = {'txName': 'Earth', 'rxName': 'Jupiter Station', 'delay': 0}
        v2 = upgrade_config(v1)
        self.assertEqual(v2['nodes'][1]['location'], 'earth')


class TestComputeSegments(unittest.TestCase):

    def setUp(self):
        self.plan = create_plan(start='2026-01-01T12:00:00Z')
        self.segs = compute_segments(self.plan)

    def test_returns_list(self):
        self.assertIsInstance(self.segs, list)

    def test_segment_count(self):
        self.assertEqual(len(self.segs), len(self.plan.segments))

    def test_first_start_equals_plan_start(self):
        self.assertEqual(self.segs[0].start, '2026-01-01T12:00:00Z')

    def test_consecutive_segments(self):
        for i in range(len(self.segs) - 1):
            self.assertEqual(self.segs[i].end, self.segs[i + 1].start)

    def test_dur_min_positive(self):
        for seg in self.segs:
            self.assertGreater(seg.dur_min, 0)

    def test_type_matches_plan(self):
        for i, seg in enumerate(self.segs):
            self.assertEqual(seg.type, self.plan.segments[i].type)


class TestTotalMin(unittest.TestCase):

    def test_total_min_default(self):
        plan = create_plan(start='2026-01-01T12:00:00Z')
        # DEFAULT_SEGMENTS has q: 2,2,2,2,2,2,1 = 13 quanta × 3 min = 39 min
        self.assertEqual(total_min(plan), 65)  # 13 quanta × 5 min (B12: default quantum 5)

    def test_total_min_custom_quantum(self):
        plan = create_plan(quantum=5, start='2026-01-01T12:00:00Z')
        # 13 quanta × 5 min = 65 min
        self.assertEqual(total_min(plan), 65)


class TestMakePlanId(unittest.TestCase):

    def setUp(self):
        self.plan = create_plan(
            title='LTX Session',
            start='2026-01-01T12:00:00Z',
            host_name='Earth HQ',
            remote_name='Mars Hab-01',
            delay=800,
        )

    def test_format(self):
        pid = make_plan_id(self.plan)
        self.assertRegex(pid, r'^LTX-\d{8}-\w+-\w+-v2-[0-9a-f]{8}$')

    def test_contains_date(self):
        pid = make_plan_id(self.plan)
        self.assertIn('20260101', pid)

    def test_deterministic(self):
        pid1 = make_plan_id(self.plan)
        pid2 = make_plan_id(self.plan)
        self.assertEqual(pid1, pid2)

    def test_different_plans_differ(self):
        plan2 = create_plan(start='2026-06-15T10:00:00Z', delay=200)
        self.assertNotEqual(make_plan_id(self.plan), make_plan_id(plan2))

    def test_host_name_in_id(self):
        pid = make_plan_id(self.plan)
        self.assertIn('EARTHHQ', pid)


class TestEncodeDecodeHash(unittest.TestCase):

    def setUp(self):
        self.plan = create_plan(
            title='Hash Test',
            start='2026-03-15T08:00:00Z',
            delay=500,
        )

    def test_encode_returns_hash_fragment(self):
        h = encode_hash(self.plan)
        self.assertTrue(h.startswith('#l='))

    def test_roundtrip(self):
        h = encode_hash(self.plan)
        decoded = decode_hash(h)
        self.assertIsNotNone(decoded)
        self.assertEqual(decoded.title, self.plan.title)
        self.assertEqual(decoded.start, self.plan.start)
        self.assertEqual(len(decoded.nodes), len(self.plan.nodes))

    def test_decode_without_hash_prefix(self):
        h = encode_hash(self.plan)
        token = h[3:]   # strip '#l='
        decoded = decode_hash(token)
        self.assertIsNotNone(decoded)
        self.assertEqual(decoded.title, self.plan.title)

    def test_decode_with_l_prefix(self):
        h = encode_hash(self.plan)
        decoded = decode_hash(h[1:])  # strip just '#'
        self.assertIsNotNone(decoded)
        self.assertEqual(decoded.title, self.plan.title)

    def test_decode_invalid_returns_none(self):
        self.assertIsNone(decode_hash('not_valid_base64!!!'))

    def test_decode_empty_returns_none(self):
        self.assertIsNone(decode_hash(''))

    def test_encode_is_url_safe(self):
        h = encode_hash(self.plan)
        token = h[3:]
        self.assertNotIn('+', token)
        self.assertNotIn('/', token)
        self.assertNotIn('=', token)


class TestBuildNodeUrls(unittest.TestCase):

    def setUp(self):
        self.plan = create_plan(start='2026-01-01T12:00:00Z', delay=800)

    def test_returns_two_urls(self):
        urls = build_node_urls(self.plan, 'https://interplanet.live/ltx.html')
        self.assertEqual(len(urls), 2)

    def test_url_format(self):
        urls = build_node_urls(self.plan, 'https://interplanet.live/ltx.html')
        for u in urls:
            self.assertIn('?node=', u.url)
            self.assertIn('#l=', u.url)

    def test_node_ids(self):
        urls = build_node_urls(self.plan, 'https://interplanet.live/ltx.html')
        self.assertEqual(urls[0].node_id, 'N0')
        self.assertEqual(urls[1].node_id, 'N1')

    def test_roles(self):
        urls = build_node_urls(self.plan, 'https://interplanet.live/ltx.html')
        self.assertEqual(urls[0].role, 'HOST')
        self.assertEqual(urls[1].role, 'PARTICIPANT')

    def test_base_url_stripped(self):
        urls = build_node_urls(self.plan, 'https://interplanet.live/ltx.html#old')
        for u in urls:
            self.assertNotIn('#old', u.url)


class TestGenerateICS(unittest.TestCase):

    def setUp(self):
        self.plan = create_plan(
            title='Mars Mission Debrief',
            start='2026-01-01T14:00:00Z',
            delay=800,
            remote_name='Mars Hab-01',
            remote_location='mars',
        )
        self.ics = generate_ics(self.plan)

    def test_begins_with_vcalendar(self):
        self.assertTrue(self.ics.startswith('BEGIN:VCALENDAR'))

    def test_ends_with_vcalendar(self):
        self.assertIn('END:VCALENDAR', self.ics)

    def test_vevent_present(self):
        self.assertIn('BEGIN:VEVENT', self.ics)
        self.assertIn('END:VEVENT', self.ics)

    def test_summary_matches_title(self):
        self.assertIn('SUMMARY:Mars Mission Debrief', self.ics)

    def test_ltx_extension_present(self):
        self.assertIn('LTX:1', self.ics)

    def test_ltx_planid_present(self):
        self.assertIn('LTX-PLANID:', self.ics)

    def test_ltx_quantum(self):
        self.assertIn('LTX-QUANTUM:PT5M', self.ics)

    def test_ltx_segment_template(self):
        self.assertIn('LTX-SEGMENT-TEMPLATE:', self.ics)

    def test_ltx_node_lines(self):
        self.assertIn('LTX-NODE:', self.ics)

    def test_ltx_delay_line(self):
        self.assertIn('LTX-DELAY', self.ics)

    def test_ltx_local_time_for_mars(self):
        self.assertIn('LTX-LOCALTIME:', self.ics)

    def test_crlf_line_endings(self):
        self.assertIn('\r\n', self.ics)

    def test_no_ltx_localtime_for_earth_only(self):
        plan_earth = create_plan(
            start='2026-01-01T14:00:00Z',
            remote_location='earth',
        )
        ics = generate_ics(plan_earth)
        self.assertNotIn('LTX-LOCALTIME:', ics)


class TestFormatHMS(unittest.TestCase):

    def test_seconds_only(self):
        self.assertEqual(format_hms(45), '00:45')

    def test_one_minute(self):
        self.assertEqual(format_hms(60), '01:00')

    def test_three_minutes(self):
        self.assertEqual(format_hms(186), '03:06')

    def test_one_hour(self):
        self.assertEqual(format_hms(3600), '01:00:00')

    def test_negative_zero(self):
        self.assertEqual(format_hms(-5), '00:00')

    def test_zero(self):
        self.assertEqual(format_hms(0), '00:00')


class TestFormatUTC(unittest.TestCase):

    def test_ms_timestamp(self):
        # J2000.0 = 946728000000 ms → 12:00:00 UTC
        result = format_utc(946728000000)
        self.assertEqual(result, '12:00:00 UTC')

    def test_iso_string(self):
        result = format_utc('2026-01-01T08:30:00Z')
        self.assertEqual(result, '08:30:00 UTC')

    def test_ends_with_utc(self):
        self.assertTrue(format_utc(0).endswith(' UTC'))


class TestCanonicalJSON(unittest.TestCase):
    """Tests for canonical_json (RFC 8785 / JCS) — Story 28.1."""

    def test_sorts_keys(self):
        obj = {'z': 1, 'a': 2, 'm': 3}
        self.assertEqual(ltx.canonical_json(obj), '{"a":2,"m":3,"z":1}')

    def test_nested_object(self):
        obj = {'b': {'y': 1, 'x': 2}, 'a': [3, 1, 2]}
        self.assertEqual(ltx.canonical_json(obj), '{"a":[3,1,2],"b":{"x":2,"y":1}}')

    def test_array_order_preserved(self):
        self.assertEqual(ltx.canonical_json([3, 1, 2]), '[3,1,2]')

    def test_null(self):
        self.assertEqual(ltx.canonical_json(None), 'null')

    def test_string(self):
        self.assertEqual(ltx.canonical_json('hi'), '"hi"')

    def test_bool_true(self):
        self.assertEqual(ltx.canonical_json(True), 'true')

    def test_bool_false(self):
        self.assertEqual(ltx.canonical_json(False), 'false')

    def test_integer(self):
        self.assertEqual(ltx.canonical_json(42), '42')

    def test_deterministic(self):
        plan = create_plan(title='Test', start='2026-03-01T12:00:00.000Z')
        # convert dataclass to dict for canonical_json
        import dataclasses
        plan_dict = dataclasses.asdict(plan)
        s1 = ltx.canonical_json(plan_dict)
        s2 = ltx.canonical_json(plan_dict)
        self.assertEqual(s1, s2)

    def test_no_structural_whitespace(self):
        obj = {'z': 1, 'a': 2}
        result = ltx.canonical_json(obj)
        self.assertNotIn(' ', result)


class TestNIK(unittest.TestCase):
    """Tests for generate_nik, nik_fingerprint, is_nik_expired — Story 28.1."""

    def setUp(self):
        try:
            self.result = ltx.generate_nik(node_label='Earth HQ')
            self.nik = self.result['nik']
            self.private_key_b64 = self.result['private_key_b64']
            self.available = True
        except ImportError:
            self.available = False

    def _require_crypto(self):
        if not self.available:
            self.skipTest('Neither cryptography nor PyNaCl is installed')

    def test_generate_returns_dict(self):
        self._require_crypto()
        self.assertIsInstance(self.result, dict)

    def test_nik_has_node_id(self):
        self._require_crypto()
        self.assertIn('nodeId', self.nik)
        self.assertIsInstance(self.nik['nodeId'], str)

    def test_node_id_length_22(self):
        self._require_crypto()
        # 16 bytes base64url (no padding) = 22 characters
        self.assertEqual(len(self.nik['nodeId']), 22)

    def test_algorithm_ed25519(self):
        self._require_crypto()
        self.assertEqual(self.nik['algorithm'], 'Ed25519')

    def test_public_key_base64url(self):
        self._require_crypto()
        import re
        self.assertRegex(self.nik['publicKey'], r'^[A-Za-z0-9_-]+$')

    def test_public_key_length_43(self):
        self._require_crypto()
        # 32 bytes base64url (no padding) = 43 characters
        self.assertEqual(len(self.nik['publicKey']), 43)

    def test_nik_has_valid_from(self):
        self._require_crypto()
        self.assertIn('validFrom', self.nik)
        self.assertIsInstance(self.nik['validFrom'], str)

    def test_nik_has_valid_until(self):
        self._require_crypto()
        self.assertIn('validUntil', self.nik)
        self.assertIsInstance(self.nik['validUntil'], str)

    def test_key_version_is_1(self):
        self._require_crypto()
        self.assertEqual(self.nik['keyVersion'], 1)

    def test_label_stored(self):
        self._require_crypto()
        self.assertEqual(self.nik.get('label'), 'Earth HQ')

    def test_no_label_when_omitted(self):
        self._require_crypto()
        result = ltx.generate_nik()
        self.assertNotIn('label', result['nik'])

    def test_private_key_present(self):
        self._require_crypto()
        self.assertIsInstance(self.private_key_b64, str)

    def test_private_key_base64url(self):
        self._require_crypto()
        import re
        self.assertRegex(self.private_key_b64, r'^[A-Za-z0-9_-]+$')

    def test_is_nik_expired_fresh(self):
        self._require_crypto()
        self.assertFalse(ltx.is_nik_expired(self.nik))

    def test_is_nik_expired_old(self):
        self._require_crypto()
        expired = {**self.nik, 'validUntil': '2020-01-01T00:00:00.000Z'}
        self.assertTrue(ltx.is_nik_expired(expired))

    def test_fingerprint_is_hex(self):
        self._require_crypto()
        fp = ltx.nik_fingerprint(self.nik)
        import re
        self.assertRegex(fp, r'^[0-9a-f]{64}$')

    def test_fingerprint_deterministic(self):
        self._require_crypto()
        fp1 = ltx.nik_fingerprint(self.nik)
        fp2 = ltx.nik_fingerprint(self.nik)
        self.assertEqual(fp1, fp2)

    def test_unique_node_ids(self):
        self._require_crypto()
        r2 = ltx.generate_nik()
        self.assertNotEqual(self.nik['nodeId'], r2['nik']['nodeId'])


class TestSignPlan(unittest.TestCase):
    """Tests for sign_plan and verify_plan — Story 28.2."""

    @classmethod
    def setUpClass(cls):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
            cls.crypto_available = True
        except ImportError:
            cls.crypto_available = False

    def setUp(self):
        if not self.crypto_available:
            self.skipTest('cryptography package not installed')
        result = ltx.generate_nik(node_label='Earth HQ')
        self.nik = result['nik']
        self.private_key_b64 = result['private_key_b64']
        self.plan = create_plan(title='Signed Session', start='2026-04-01T12:00:00.000Z')

    def test_sign_plan_returns_dict(self):
        signed = ltx.sign_plan(self._plan_dict(), self.private_key_b64)
        self.assertIsInstance(signed, dict)

    def _plan_dict(self):
        import dataclasses
        return dataclasses.asdict(self.plan)

    def test_sign_plan_has_cose_sign1(self):
        signed = ltx.sign_plan(self._plan_dict(), self.private_key_b64)
        self.assertIn('coseSign1', signed)
        self.assertIsInstance(signed['coseSign1'], dict)

    def test_cose_sign1_fields(self):
        signed = ltx.sign_plan(self._plan_dict(), self.private_key_b64)
        cs = signed['coseSign1']
        self.assertIn('protected', cs)
        self.assertIn('payload', cs)
        self.assertIn('signature', cs)
        self.assertIn('unprotected', cs)
        self.assertIn('kid', cs['unprotected'])

    def test_signature_url_safe(self):
        import re
        signed = ltx.sign_plan(self._plan_dict(), self.private_key_b64)
        self.assertRegex(signed['coseSign1']['signature'], r'^[A-Za-z0-9_-]+$')

    def test_payload_decodes_to_plan_json(self):
        import base64
        plan_dict = self._plan_dict()
        signed = ltx.sign_plan(plan_dict, self.private_key_b64)
        decoded = base64.urlsafe_b64decode(signed['coseSign1']['payload'] + '==').decode()
        self.assertEqual(decoded, ltx.canonical_json(plan_dict))

    def test_verify_plan_valid(self):
        plan_dict = self._plan_dict()
        signed = ltx.sign_plan(plan_dict, self.private_key_b64)
        key_cache = {self.nik['nodeId']: self.nik}
        result = ltx.verify_plan(signed, key_cache)
        self.assertTrue(result['valid'])

    def test_verify_plan_tampered_payload(self):
        import base64
        plan_dict = self._plan_dict()
        signed = ltx.sign_plan(plan_dict, self.private_key_b64)
        # Tamper the payload
        tampered = dict(signed)
        hacked = dict(plan_dict)
        hacked['title'] = 'HACKED'
        tampered['coseSign1'] = dict(signed['coseSign1'])
        tampered['coseSign1']['payload'] = base64.urlsafe_b64encode(
            ltx.canonical_json(hacked).encode()
        ).rstrip(b'=').decode()
        key_cache = {self.nik['nodeId']: self.nik}
        result = ltx.verify_plan(tampered, key_cache)
        self.assertFalse(result['valid'])

    def test_verify_plan_wrong_key(self):
        plan_dict = self._plan_dict()
        signed = ltx.sign_plan(plan_dict, self.private_key_b64)
        wrong_result = ltx.generate_nik()
        wrong_cache = {wrong_result['nik']['nodeId']: wrong_result['nik']}
        result = ltx.verify_plan(signed, wrong_cache)
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'key_not_in_cache')

    def test_verify_plan_expired_key(self):
        plan_dict = self._plan_dict()
        signed = ltx.sign_plan(plan_dict, self.private_key_b64)
        expired_nik = {**self.nik, 'validUntil': '2020-01-01T00:00:00.000Z'}
        key_cache = {expired_nik['nodeId']: expired_nik}
        result = ltx.verify_plan(signed, key_cache)
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'key_expired')

    def test_verify_plan_missing_cose(self):
        plan_dict = self._plan_dict()
        result = ltx.verify_plan({'plan': plan_dict}, {})
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'missing_cose_sign1')


class TestSequenceTracker(unittest.TestCase):
    """Tests for SequenceTracker, add_seq, check_seq — Story 28.4."""

    def setUp(self):
        self.tracker = ltx.SequenceTracker('plan-abc-123')

    # ── next_seq ──────────────────────────────────────────────────────────────

    def test_next_seq_starts_at_1(self):
        self.assertEqual(self.tracker.next_seq('N0'), 1)

    def test_next_seq_increments(self):
        self.tracker.next_seq('N0')
        self.assertEqual(self.tracker.next_seq('N0'), 2)

    def test_next_seq_nodes_independent(self):
        self.tracker.next_seq('N0')
        self.tracker.next_seq('N0')
        self.assertEqual(self.tracker.next_seq('N1'), 1)

    # ── record_seq — acceptance ───────────────────────────────────────────────

    def test_record_seq_accepts_1(self):
        result = self.tracker.record_seq('N0', 1)
        self.assertTrue(result['accepted'])
        self.assertFalse(result['gap'])

    def test_record_seq_accepts_2(self):
        self.tracker.record_seq('N0', 1)
        result = self.tracker.record_seq('N0', 2)
        self.assertTrue(result['accepted'])

    # ── record_seq — replay rejection ─────────────────────────────────────────

    def test_record_seq_rejects_replay(self):
        self.tracker.record_seq('N0', 1)
        self.tracker.record_seq('N0', 2)
        result = self.tracker.record_seq('N0', 1)
        self.assertFalse(result['accepted'])
        self.assertEqual(result['reason'], 'replay')

    def test_record_seq_rejects_same_seq(self):
        self.tracker.record_seq('N0', 3)
        result = self.tracker.record_seq('N0', 3)
        self.assertFalse(result['accepted'])

    # ── record_seq — gap detection ────────────────────────────────────────────

    def test_record_seq_detects_gap(self):
        self.tracker.record_seq('N0', 1)
        self.tracker.record_seq('N0', 2)
        result = self.tracker.record_seq('N0', 5)  # skip 3, 4
        self.assertTrue(result['accepted'])
        self.assertTrue(result['gap'])
        self.assertEqual(result['gap_size'], 2)

    def test_record_seq_no_gap_on_consecutive(self):
        self.tracker.record_seq('N0', 4)
        result = self.tracker.record_seq('N0', 5)
        self.assertTrue(result['accepted'])
        self.assertFalse(result['gap'])
        self.assertEqual(result['gap_size'], 0)

    def test_record_seq_after_gap_accepted(self):
        self.tracker.record_seq('N0', 2)
        self.tracker.record_seq('N0', 5)
        result = self.tracker.record_seq('N0', 6)
        self.assertTrue(result['accepted'])
        self.assertFalse(result['gap'])

    # ── last_seen_seq / current_seq ───────────────────────────────────────────

    def test_last_seen_seq_initial(self):
        self.assertEqual(self.tracker.last_seen_seq('N0'), 0)

    def test_last_seen_seq_after_records(self):
        self.tracker.record_seq('N0', 1)
        self.tracker.record_seq('N0', 2)
        self.tracker.record_seq('N0', 5)
        self.tracker.record_seq('N0', 6)
        self.assertEqual(self.tracker.last_seen_seq('N0'), 6)

    def test_current_seq_initial(self):
        self.assertEqual(self.tracker.current_seq('N0'), 0)

    def test_current_seq_after_next_seq(self):
        self.tracker.next_seq('N0')
        self.tracker.next_seq('N0')
        self.assertEqual(self.tracker.current_seq('N0'), 2)

    # ── snapshot ──────────────────────────────────────────────────────────────

    def test_snapshot_returns_dict(self):
        self.tracker.next_seq('N0')
        snap = self.tracker.snapshot()
        self.assertIsInstance(snap, dict)

    def test_snapshot_contains_state(self):
        self.tracker.next_seq('N0')
        self.tracker.record_seq('N0', 5)
        snap = self.tracker.snapshot()
        self.assertTrue(len(snap) > 0)

    # ── add_seq ───────────────────────────────────────────────────────────────

    def test_add_seq_adds_field(self):
        tracker2 = ltx.SequenceTracker('plan-xyz')
        bundle = {'type': 'TX', 'content': 'hello'}
        result = ltx.add_seq(bundle, tracker2, 'N0')
        self.assertIn('seq', result)
        self.assertEqual(result['seq'], 1)

    def test_add_seq_preserves_bundle(self):
        tracker2 = ltx.SequenceTracker('plan-xyz')
        bundle = {'type': 'TX', 'content': 'hello'}
        result = ltx.add_seq(bundle, tracker2, 'N0')
        self.assertEqual(result['type'], 'TX')
        self.assertEqual(result['content'], 'hello')

    def test_add_seq_does_not_mutate_original(self):
        tracker2 = ltx.SequenceTracker('plan-xyz')
        bundle = {'type': 'TX'}
        ltx.add_seq(bundle, tracker2, 'N0')
        self.assertNotIn('seq', bundle)

    # ── check_seq ─────────────────────────────────────────────────────────────

    def test_check_seq_accepts_first(self):
        tracker2 = ltx.SequenceTracker('plan-xyz')
        bundle = {'type': 'TX', 'seq': 1}
        result = ltx.check_seq(bundle, tracker2, 'N0')
        self.assertTrue(result['accepted'])

    def test_check_seq_rejects_replay(self):
        tracker2 = ltx.SequenceTracker('plan-xyz')
        bundle = {'type': 'TX', 'seq': 1}
        ltx.check_seq(bundle, tracker2, 'N0')
        result = ltx.check_seq(bundle, tracker2, 'N0')
        self.assertFalse(result['accepted'])

    def test_check_seq_missing_seq(self):
        tracker2 = ltx.SequenceTracker('plan-xyz')
        result = ltx.check_seq({'type': 'TX'}, tracker2, 'N0')
        self.assertFalse(result['accepted'])
        self.assertEqual(result['reason'], 'missing_seq')

    def test_check_seq_add_seq_roundtrip(self):
        tracker_tx = ltx.SequenceTracker('plan-rt')
        tracker_rx = ltx.SequenceTracker('plan-rt')
        bundle = {'type': 'TX'}
        seq_bundle = ltx.add_seq(bundle, tracker_tx, 'N0')
        result = ltx.check_seq(seq_bundle, tracker_rx, 'N0')
        self.assertTrue(result['accepted'])


class TestMerkleLog(unittest.TestCase):
    """Tests for MerkleLog and verify_tree_head — Story 28.5."""

    @classmethod
    def setUpClass(cls):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
            cls.crypto_available = True
        except ImportError:
            cls.crypto_available = False

    def _require_crypto(self):
        if not self.crypto_available:
            self.skipTest('cryptography package not installed')

    # ── Empty log ─────────────────────────────────────────────────────────────

    def test_empty_tree_size(self):
        log = ltx.MerkleLog()
        self.assertEqual(log.tree_size(), 0)

    def test_empty_root_is_64_zeros(self):
        log = ltx.MerkleLog()
        self.assertEqual(log.root_hex(), '0' * 64)

    # ── Append ────────────────────────────────────────────────────────────────

    def test_append_returns_tree_size_1(self):
        log = ltx.MerkleLog()
        result = log.append({'type': 'TX', 'seq': 1, 'data': 'hello'})
        self.assertEqual(result['tree_size'], 1)

    def test_append_returns_root_hex(self):
        log = ltx.MerkleLog()
        result = log.append({'type': 'TX', 'seq': 1})
        self.assertIsInstance(result['root'], str)
        self.assertEqual(len(result['root']), 64)

    def test_append_two_returns_tree_size_2(self):
        log = ltx.MerkleLog()
        log.append({'type': 'TX', 'seq': 1, 'data': 'hello'})
        result = log.append({'type': 'RX', 'seq': 2, 'data': 'world'})
        self.assertEqual(result['tree_size'], 2)

    def test_root_changes_on_append(self):
        log = ltx.MerkleLog()
        r1 = log.append({'type': 'TX', 'seq': 1, 'data': 'hello'})
        r2 = log.append({'type': 'RX', 'seq': 2, 'data': 'world'})
        self.assertNotEqual(r1['root'], r2['root'])

    def test_tree_size_after_15_appends(self):
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        self.assertEqual(log.tree_size(), 15)

    # ── Root stability ────────────────────────────────────────────────────────

    def test_roots_differ_at_10_and_15(self):
        log = ltx.MerkleLog()
        for i in range(1, 11):
            log.append({'seq': i})
        root10 = log.root_hex()
        for i in range(11, 16):
            log.append({'seq': i})
        root15 = log.root_hex()
        self.assertNotEqual(root10, root15)

    def test_identical_logs_same_root(self):
        log1 = ltx.MerkleLog()
        log2 = ltx.MerkleLog()
        for i in range(1, 16):
            log1.append({'seq': i})
            log2.append({'seq': i})
        self.assertEqual(log1.root_hex(), log2.root_hex())

    # ── Inclusion proof ───────────────────────────────────────────────────────

    def test_inclusion_proof_returns_list(self):
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        proof = log.inclusion_proof(2)
        self.assertIsInstance(proof, list)

    def test_inclusion_proof_elements(self):
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        proof = log.inclusion_proof(2)
        for step in proof:
            self.assertIn(step['side'], ('left', 'right'))
            self.assertIsInstance(step['hash'], str)
            self.assertEqual(len(step['hash']), 64)

    def test_verify_inclusion_valid(self):
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        root15 = log.root_hex()
        proof = log.inclusion_proof(2)
        self.assertTrue(log.verify_inclusion({'seq': 3}, 2, proof, root15))

    def test_verify_inclusion_tampered_entry(self):
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        root15 = log.root_hex()
        proof = log.inclusion_proof(2)
        self.assertFalse(log.verify_inclusion({'seq': 999}, 2, proof, root15))

    def test_inclusion_proof_out_of_range(self):
        log = ltx.MerkleLog()
        log.append({'seq': 1})
        with self.assertRaises(IndexError):
            log.inclusion_proof(5)

    # ── Consistency proof ─────────────────────────────────────────────────────

    def test_consistency_proof_returns_list(self):
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        proof = log.consistency_proof(10)
        self.assertIsInstance(proof, list)

    def test_consistency_proof_same_size_empty(self):
        log = ltx.MerkleLog()
        for i in range(1, 11):
            log.append({'seq': i})
        self.assertEqual(log.consistency_proof(10), [])

    def test_consistency_proof_old_size_exceeds_raises(self):
        log = ltx.MerkleLog()
        for i in range(1, 6):
            log.append({'seq': i})
        with self.assertRaises(ValueError):
            log.consistency_proof(10)

    # ── Signed tree head ──────────────────────────────────────────────────────

    def test_sign_tree_head_has_tree_size(self):
        self._require_crypto()
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        result = ltx.generate_nik()
        head = log.sign_tree_head(result['private_key_b64'], result['nik']['nodeId'])
        self.assertEqual(head['treeSize'], 15)

    def test_sign_tree_head_has_root(self):
        self._require_crypto()
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        root15 = log.root_hex()
        result = ltx.generate_nik()
        head = log.sign_tree_head(result['private_key_b64'], result['nik']['nodeId'])
        self.assertEqual(head['sha256RootHash'], root15)

    def test_sign_tree_head_has_sig(self):
        self._require_crypto()
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        result = ltx.generate_nik()
        head = log.sign_tree_head(result['private_key_b64'], result['nik']['nodeId'])
        self.assertIsInstance(head['treeHeadSig'], str)
        self.assertGreater(len(head['treeHeadSig']), 0)

    def test_verify_tree_head_valid(self):
        self._require_crypto()
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        result = ltx.generate_nik()
        head = log.sign_tree_head(result['private_key_b64'], result['nik']['nodeId'])
        self.assertTrue(ltx.verify_tree_head(head, result['nik']))

    def test_verify_tree_head_wrong_key(self):
        self._require_crypto()
        log = ltx.MerkleLog()
        for i in range(1, 16):
            log.append({'seq': i})
        result = ltx.generate_nik()
        head = log.sign_tree_head(result['private_key_b64'], result['nik']['nodeId'])
        wrong = ltx.generate_nik()
        self.assertFalse(ltx.verify_tree_head(head, wrong['nik']))


class TestKeyDistribution(unittest.TestCase):
    """Tests for create_key_bundle, verify_and_cache_keys, create_revocation, apply_revocation.
    Story 28.6 — Pre-session key distribution (KEY_BUNDLE protocol).
    """

    @classmethod
    def setUpClass(cls):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
            cls.crypto_available = True
        except ImportError:
            cls.crypto_available = False

    def setUp(self):
        if not self.crypto_available:
            self.skipTest('cryptography package not installed')
        host_result = ltx.generate_nik(node_label='Earth HQ')
        self.host_nik = host_result['nik']
        self.host_priv = host_result['private_key_b64']
        self.part_nik = ltx.generate_nik(node_label='Mars Hab')['nik']
        self.eok_nik = ltx.generate_nik(node_label='Emergency Override')['nik']

    # ── create_key_bundle ─────────────────────────────────────────────────────

    def test_create_key_bundle_type(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        self.assertEqual(kb['type'], 'KEY_BUNDLE')

    def test_create_key_bundle_plan_id(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        self.assertEqual(kb['planId'], 'plan-001')

    def test_create_key_bundle_keys_array(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik, self.eok_nik], self.host_priv)
        self.assertIsInstance(kb['keys'], list)
        self.assertEqual(len(kb['keys']), 3)

    def test_create_key_bundle_has_bundle_sig(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik], self.host_priv)
        self.assertIn('bundleSig', kb)
        self.assertIsInstance(kb['bundleSig'], str)

    def test_create_key_bundle_has_timestamp(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik], self.host_priv)
        self.assertIn('timestamp', kb)
        self.assertIsInstance(kb['timestamp'], str)

    def test_bundle_sig_url_safe(self):
        import re
        kb = ltx.create_key_bundle('plan-001', [self.host_nik], self.host_priv)
        self.assertRegex(kb['bundleSig'], r'^[A-Za-z0-9_-]+$')

    # ── verify_and_cache_keys ─────────────────────────────────────────────────

    def test_verify_and_cache_keys_returns_dict(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik, self.eok_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        self.assertIsInstance(cache, dict)

    def test_cache_has_three_entries(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik, self.eok_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        self.assertEqual(len(cache), 3)

    def test_cache_has_host_nik(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        self.assertIn(self.host_nik['nodeId'], cache)

    def test_cache_has_part_nik(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        self.assertIn(self.part_nik['nodeId'], cache)

    def test_wrong_bootstrap_key_returns_none(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        wrong_nik = ltx.generate_nik()['nik']
        result = ltx.verify_and_cache_keys(kb, wrong_nik)
        self.assertIsNone(result)

    def test_tampered_bundle_returns_none(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        extra_nik = ltx.generate_nik()['nik']
        tampered = {**kb, 'keys': kb['keys'] + [extra_nik]}
        result = ltx.verify_and_cache_keys(tampered, self.host_nik)
        self.assertIsNone(result)

    def test_wrong_type_returns_none(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik], self.host_priv)
        bad = {**kb, 'type': 'INVALID'}
        result = ltx.verify_and_cache_keys(bad, self.host_nik)
        self.assertIsNone(result)

    def test_expired_nik_excluded_from_cache(self):
        expired_nik = {**ltx.generate_nik()['nik'], 'validUntil': '2020-01-01T00:00:00.000Z'}
        kb = ltx.create_key_bundle('plan-exp', [self.host_nik, expired_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        self.assertIsNotNone(cache)
        self.assertNotIn(expired_nik['nodeId'], cache)

    def test_valid_nik_included_when_expired_present(self):
        expired_nik = {**ltx.generate_nik()['nik'], 'validUntil': '2020-01-01T00:00:00.000Z'}
        kb = ltx.create_key_bundle('plan-exp', [self.host_nik, expired_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        self.assertIn(self.host_nik['nodeId'], cache)

    # ── create_revocation ─────────────────────────────────────────────────────

    def test_create_revocation_type(self):
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'compromised', self.host_priv)
        self.assertEqual(rev['type'], 'KEY_REVOCATION')

    def test_create_revocation_node_id(self):
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'compromised', self.host_priv)
        self.assertEqual(rev['nodeId'], self.part_nik['nodeId'])

    def test_create_revocation_has_sig(self):
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'compromised', self.host_priv)
        self.assertIn('revocationSig', rev)
        self.assertIsInstance(rev['revocationSig'], str)

    def test_create_revocation_reason(self):
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'key_leak', self.host_priv)
        self.assertEqual(rev['reason'], 'key_leak')

    def test_revocation_sig_url_safe(self):
        import re
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'expired', self.host_priv)
        self.assertRegex(rev['revocationSig'], r'^[A-Za-z0-9_-]+$')

    # ── apply_revocation ──────────────────────────────────────────────────────

    def test_apply_revocation_returns_true(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'compromised', self.host_priv)
        result = ltx.apply_revocation(cache, rev)
        self.assertTrue(result)

    def test_apply_revocation_removes_key(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'compromised', self.host_priv)
        ltx.apply_revocation(cache, rev)
        self.assertNotIn(self.part_nik['nodeId'], cache)

    def test_apply_revocation_keeps_other_keys(self):
        kb = ltx.create_key_bundle('plan-001', [self.host_nik, self.part_nik], self.host_priv)
        cache = ltx.verify_and_cache_keys(kb, self.host_nik)
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'compromised', self.host_priv)
        ltx.apply_revocation(cache, rev)
        self.assertIn(self.host_nik['nodeId'], cache)

    def test_apply_revocation_wrong_type_returns_false(self):
        cache = {self.part_nik['nodeId']: self.part_nik}
        bad_rev = {'type': 'INVALID', 'nodeId': self.part_nik['nodeId']}
        result = ltx.apply_revocation(cache, bad_rev)
        self.assertFalse(result)

    def test_apply_revocation_nonexistent_key_ok(self):
        # Revoking a key not in cache should not raise, just return True
        cache = {}
        rev = ltx.create_revocation('plan-001', self.part_nik['nodeId'], 'test', self.host_priv)
        result = ltx.apply_revocation(cache, rev)
        self.assertTrue(result)


class TestBPSecBIB(unittest.TestCase):
    """Story 28.3 — BPSec Bundle Integrity Block (RFC 9173, Context ID 1)."""

    def setUp(self):
        self.key = ltx.generate_bib_key()
        self.bundle = {'type': 'TX', 'seq': 1, 'data': 'hello mars'}

    # 1. add_bib returns a dict with a 'bib' field
    def test_add_bib_returns_bib_field(self):
        result = ltx.add_bib(self.bundle, self.key)
        self.assertIn('bib', result)
        self.assertIsInstance(result['bib'], dict)

    # 2. bib['contextId'] == 1
    def test_bib_context_id(self):
        result = ltx.add_bib(self.bundle, self.key)
        self.assertEqual(result['bib']['contextId'], 1)

    # 3. bib['targetBlockNumber'] == 0
    def test_bib_target_block_number(self):
        result = ltx.add_bib(self.bundle, self.key)
        self.assertEqual(result['bib']['targetBlockNumber'], 0)

    # 4. bib['hmac'] is a non-empty string
    def test_bib_hmac_is_string(self):
        result = ltx.add_bib(self.bundle, self.key)
        self.assertIsInstance(result['bib']['hmac'], str)
        self.assertGreater(len(result['bib']['hmac']), 0)

    # 5. verify_bib with correct key → {'valid': True}
    def test_verify_bib_correct_key(self):
        with_bib = ltx.add_bib(self.bundle, self.key)
        result = ltx.verify_bib(with_bib, self.key)
        self.assertTrue(result['valid'])

    # 6. verify_bib with tampered payload → {'valid': False}
    def test_verify_bib_tampered_payload(self):
        with_bib = ltx.add_bib(self.bundle, self.key)
        tampered = dict(with_bib)
        tampered['data'] = 'HACKED'
        result = ltx.verify_bib(tampered, self.key)
        self.assertFalse(result['valid'])

    # 7. verify_bib with wrong key → {'valid': False, 'reason': 'hmac_mismatch'}
    def test_verify_bib_wrong_key(self):
        with_bib = ltx.add_bib(self.bundle, self.key)
        wrong_key = ltx.generate_bib_key()
        result = ltx.verify_bib(with_bib, wrong_key)
        self.assertFalse(result['valid'])
        self.assertEqual(result.get('reason'), 'hmac_mismatch')

    # 8. verify_bib with no bib field → {'valid': False, 'reason': 'missing_bib'}
    def test_verify_bib_missing_bib(self):
        result = ltx.verify_bib(self.bundle, self.key)
        self.assertFalse(result['valid'])
        self.assertEqual(result.get('reason'), 'missing_bib')

    # 9. add_bib does not mutate the original bundle
    def test_add_bib_no_mutation(self):
        original_keys = set(self.bundle.keys())
        ltx.add_bib(self.bundle, self.key)
        self.assertEqual(set(self.bundle.keys()), original_keys)
        self.assertNotIn('bib', self.bundle)

    # 10. generate_bib_key returns a 43-char base64url string (256-bit, no padding)
    def test_generate_bib_key_length(self):
        key = ltx.generate_bib_key()
        self.assertIsInstance(key, str)
        self.assertEqual(len(key), 43)


class TestEOKMultiAuth(unittest.TestCase):
    """Tests for create_eok, create_emergency_override, verify_emergency_override,
    create_co_sig, check_multi_auth — Story 28.7."""

    @classmethod
    def setUpClass(cls):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
            cls.crypto_available = True
        except ImportError:
            cls.crypto_available = False

    def setUp(self):
        if not self.crypto_available:
            self.skipTest('cryptography package not installed')
        self.eok_result = ltx.create_eok()
        self.eok = self.eok_result['eok']
        self.eok_priv = self.eok_result['private_key']

    # ── create_eok ─────────────────────────────────────────────────────────────

    def test_create_eok_returns_dict_with_eok(self):
        """1. createEOK() returns object with eok field."""
        self.assertIn('eok', self.eok_result)
        self.assertIsInstance(self.eok_result['eok'], dict)

    def test_create_eok_returns_dict_with_private_key(self):
        self.assertIn('private_key', self.eok_result)
        self.assertIsInstance(self.eok_result['private_key'], str)

    def test_eok_key_type_is_eok(self):
        """2. eok.keyType === 'eok'."""
        self.assertEqual(self.eok['keyType'], 'eok')

    def test_eok_algorithm_ed25519(self):
        self.assertEqual(self.eok['algorithm'], 'Ed25519')

    def test_eok_has_eok_id(self):
        self.assertIn('eokId', self.eok)
        self.assertIsInstance(self.eok['eokId'], str)

    def test_eok_has_public_key(self):
        self.assertIn('publicKey', self.eok)
        self.assertIsInstance(self.eok['publicKey'], str)

    def test_eok_has_valid_from(self):
        self.assertIn('validFrom', self.eok)

    def test_eok_has_valid_until(self):
        self.assertIn('validUntil', self.eok)

    def test_eok_default_30_days(self):
        from datetime import datetime, timezone
        valid_from  = datetime.fromisoformat(self.eok['validFrom'].replace('Z', '+00:00'))
        valid_until = datetime.fromisoformat(self.eok['validUntil'].replace('Z', '+00:00'))
        delta = valid_until - valid_from
        self.assertGreater(delta.days, 28)
        self.assertLessEqual(delta.days, 31)

    # ── create_emergency_override ─────────────────────────────────────────────

    def test_create_emergency_override_type(self):
        """3. create_emergency_override returns object with type EMERGENCY_OVERRIDE."""
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        self.assertEqual(override['type'], 'EMERGENCY_OVERRIDE')

    def test_create_emergency_override_plan_id(self):
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        self.assertEqual(override['planId'], 'plan-eok-001')

    def test_create_emergency_override_action(self):
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        self.assertEqual(override['action'], 'ABORT')

    def test_override_sig_is_non_empty_string(self):
        """4. overrideSig is a non-empty string."""
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        self.assertIn('overrideSig', override)
        self.assertIsInstance(override['overrideSig'], str)
        self.assertGreater(len(override['overrideSig']), 0)

    def test_override_sig_url_safe(self):
        import re
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        self.assertRegex(override['overrideSig'], r'^[A-Za-z0-9_-]+$')

    # ── verify_emergency_override ─────────────────────────────────────────────

    def test_verify_emergency_override_valid(self):
        """5. verify_emergency_override with correct EOK → { valid: True }."""
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        eok_cache = {self.eok['eokId']: self.eok}
        result = ltx.verify_emergency_override(override, eok_cache)
        self.assertTrue(result['valid'])

    def test_verify_emergency_override_tampered_action(self):
        """6. verify_emergency_override with tampered action → { valid: False }."""
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        tampered = dict(override)
        tampered['action'] = 'TAMPERED'
        eok_cache = {self.eok['eokId']: self.eok}
        result = ltx.verify_emergency_override(tampered, eok_cache)
        self.assertFalse(result['valid'])

    def test_verify_emergency_override_key_not_in_cache(self):
        """7. verify_emergency_override with EOK not in cache → key_not_in_cache."""
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        result = ltx.verify_emergency_override(override, {})
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'key_not_in_cache')

    def test_verify_emergency_override_expired_key(self):
        expired_eok = {**self.eok, 'validUntil': '2020-01-01T00:00:00.000Z'}
        override = ltx.create_emergency_override('plan-eok-001', 'ABORT', self.eok_priv, self.eok['eokId'])
        eok_cache = {self.eok['eokId']: expired_eok}
        result = ltx.verify_emergency_override(override, eok_cache)
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'key_expired')

    # ── create_co_sig ─────────────────────────────────────────────────────────

    def test_create_co_sig_type(self):
        """8. create_co_sig returns object with type ACTION_COSIG."""
        nik_result = ltx.generate_nik(node_label='Cosigner 1')
        cosig = ltx.create_co_sig(
            'entry-001', 'plan-multi-001',
            nik_result['nik']['nodeId'],
            nik_result['private_key_b64'],
            nik_result['nik'],
        )
        self.assertEqual(cosig['type'], 'ACTION_COSIG')

    def test_create_co_sig_entry_id(self):
        nik_result = ltx.generate_nik()
        cosig = ltx.create_co_sig(
            'entry-abc', 'plan-multi-001',
            nik_result['nik']['nodeId'],
            nik_result['private_key_b64'],
            nik_result['nik'],
        )
        self.assertEqual(cosig['entryId'], 'entry-abc')

    def test_create_co_sig_has_cosig_sig(self):
        nik_result = ltx.generate_nik()
        cosig = ltx.create_co_sig(
            'entry-001', 'plan-multi-001',
            nik_result['nik']['nodeId'],
            nik_result['private_key_b64'],
            nik_result['nik'],
        )
        self.assertIn('cosigSig', cosig)
        self.assertIsInstance(cosig['cosigSig'], str)
        self.assertGreater(len(cosig['cosigSig']), 0)

    # ── check_multi_auth ──────────────────────────────────────────────────────

    def test_check_multi_auth_two_valid_authorised(self):
        """9. check_multi_auth with 2 valid cosigs, required_count=2 → authorised True."""
        r1 = ltx.generate_nik(node_label='Cosigner 1')
        r2 = ltx.generate_nik(node_label='Cosigner 2')
        cosig1 = ltx.create_co_sig('entry-001', 'plan-multi-001', r1['nik']['nodeId'], r1['private_key_b64'], r1['nik'])
        cosig2 = ltx.create_co_sig('entry-001', 'plan-multi-001', r2['nik']['nodeId'], r2['private_key_b64'], r2['nik'])
        key_cache = {
            r1['nik']['nodeId']: r1['nik'],
            r2['nik']['nodeId']: r2['nik'],
        }
        result = ltx.check_multi_auth([cosig1, cosig2], 'entry-001', 'plan-multi-001', key_cache, 2)
        self.assertTrue(result['authorised'])
        self.assertEqual(result['valid_sig_count'], 2)

    def test_check_multi_auth_one_valid_not_authorised(self):
        """10. check_multi_auth with 1 valid cosig, required_count=2 → authorised False."""
        r1 = ltx.generate_nik(node_label='Cosigner 1')
        r2 = ltx.generate_nik(node_label='Cosigner 2')
        cosig1 = ltx.create_co_sig('entry-001', 'plan-multi-001', r1['nik']['nodeId'], r1['private_key_b64'], r1['nik'])
        key_cache = {
            r1['nik']['nodeId']: r1['nik'],
            r2['nik']['nodeId']: r2['nik'],
        }
        result = ltx.check_multi_auth([cosig1], 'entry-001', 'plan-multi-001', key_cache, 2)
        self.assertFalse(result['authorised'])
        self.assertEqual(result['valid_sig_count'], 1)

    def test_check_multi_auth_wrong_plan_id_is_invalid(self):
        r1 = ltx.generate_nik()
        cosig1 = ltx.create_co_sig('entry-001', 'plan-multi-001', r1['nik']['nodeId'], r1['private_key_b64'], r1['nik'])
        wrong_plan_cosig = {**cosig1, 'planId': 'wrong-plan'}
        key_cache = {r1['nik']['nodeId']: r1['nik']}
        result = ltx.check_multi_auth([wrong_plan_cosig], 'entry-001', 'plan-multi-001', key_cache, 1)
        self.assertFalse(result['authorised'])
        self.assertEqual(result['invalid_count'], 1)

    def test_check_multi_auth_invalid_sig_is_invalid(self):
        r1 = ltx.generate_nik()
        r2 = ltx.generate_nik()
        cosig1 = ltx.create_co_sig('entry-001', 'plan-multi-001', r1['nik']['nodeId'], r1['private_key_b64'], r1['nik'])
        # Sign with r2's key but claim r1's nodeId — signature will be invalid
        cosig_bad = ltx.create_co_sig('entry-001', 'plan-multi-001', r1['nik']['nodeId'], r2['private_key_b64'], r1['nik'])
        key_cache = {r1['nik']['nodeId']: r1['nik']}
        result = ltx.check_multi_auth([cosig1, cosig_bad], 'entry-001', 'plan-multi-001', key_cache, 2)
        self.assertFalse(result['authorised'])
        self.assertEqual(result['valid_sig_count'], 1)
        self.assertEqual(result['invalid_count'], 1)


class TestWindowManifest(unittest.TestCase):
    """Tests for artefact_sha256, create_window_manifest, verify_window_manifest,
    hedged_sign, hedged_verify — Story 28.8."""

    @classmethod
    def setUpClass(cls):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
            cls.crypto_available = True
        except ImportError:
            cls.crypto_available = False

    def setUp(self):
        if not self.crypto_available:
            self.skipTest('cryptography package not installed')
        host_result = ltx.generate_nik(node_label='Manifest Signer')
        self.signer_nik = host_result['nik']
        self.signer_priv = host_result['private_key_b64']
        # Build a small merkle log and sign a tree head
        from interplanet_ltx import MerkleLog
        log = MerkleLog()
        for i in range(1, 48):
            log.append({'seq': i})
        self.tree_head = log.sign_tree_head(self.signer_priv, self.signer_nik['nodeId'])
        self.artefacts = [
            {
                'name': 'tx-content',
                'sha256': ltx.artefact_sha256('hello world'),
                'sizeBytes': 11,
            }
        ]

    # ── artefact_sha256 ───────────────────────────────────────────────────────

    def test_artefact_sha256_returns_64_char_hex(self):
        h = ltx.artefact_sha256('hello')
        self.assertIsInstance(h, str)
        self.assertEqual(len(h), 64)

    def test_artefact_sha256_is_hex_chars(self):
        import re
        h = ltx.artefact_sha256('hello')
        self.assertRegex(h, r'^[0-9a-f]{64}$')

    # ── create_window_manifest ────────────────────────────────────────────────

    def test_create_manifest_type(self):
        m = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        self.assertEqual(m['type'], 'WINDOW_MANIFEST')

    def test_create_manifest_window_seq(self):
        m = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        self.assertEqual(m['windowSeq'], 3)

    def test_create_manifest_nonce_salt_non_empty(self):
        m = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        self.assertIsInstance(m['nonceSalt'], str)
        self.assertGreater(len(m['nonceSalt']), 0)

    def test_create_manifest_sig_non_empty(self):
        m = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        self.assertIsInstance(m['manifestSig'], str)
        self.assertGreater(len(m['manifestSig']), 0)

    def test_create_manifest_unique_nonce_salt(self):
        m1 = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        m2 = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        self.assertNotEqual(m1['nonceSalt'], m2['nonceSalt'])

    # ── verify_window_manifest ────────────────────────────────────────────────

    def test_verify_manifest_valid(self):
        m = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        key_cache = {self.signer_nik['nodeId']: self.signer_nik}
        result = ltx.verify_window_manifest(m, key_cache)
        self.assertTrue(result['valid'])

    def test_verify_manifest_tampered_artefact(self):
        m = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        import copy
        tampered = copy.deepcopy(m)
        tampered['artefacts'][0]['sha256'] = 'a' * 64
        key_cache = {self.signer_nik['nodeId']: self.signer_nik}
        result = ltx.verify_window_manifest(tampered, key_cache)
        self.assertFalse(result['valid'])

    def test_verify_manifest_key_not_in_cache(self):
        m = ltx.create_window_manifest(
            'plan-wm-001', 3, self.artefacts, self.tree_head, self.signer_priv
        )
        wrong_nik = ltx.generate_nik()['nik']
        wrong_cache = {wrong_nik['nodeId']: wrong_nik}
        result = ltx.verify_window_manifest(m, wrong_cache)
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'key_not_in_cache')

    # ── hedged_sign / hedged_verify ───────────────────────────────────────────

    def test_hedged_sign_returns_signature_and_nonce(self):
        result = ltx.hedged_sign(b'test data', self.signer_priv)
        self.assertIn('signature', result)
        self.assertIn('nonceSalt', result)
        self.assertIsInstance(result['signature'], str)
        self.assertIsInstance(result['nonceSalt'], str)

    def test_hedged_verify_valid(self):
        data = b'test data for hedged sign'
        result = ltx.hedged_sign(data, self.signer_priv)
        valid = ltx.hedged_verify(
            data, result['signature'], result['nonceSalt'], self.signer_nik['publicKey']
        )
        self.assertTrue(valid)

    def test_hedged_verify_tampered_data(self):
        data = b'test data for hedged sign'
        result = ltx.hedged_sign(data, self.signer_priv)
        valid = ltx.hedged_verify(
            b'tampered data', result['signature'], result['nonceSalt'],
            self.signer_nik['publicKey']
        )
        self.assertFalse(valid)


class TestIntegrationWithInterplanetTime(unittest.TestCase):
    """Optional integration tests — skip if interplanet_time is not installed."""

    @classmethod
    def setUpClass(cls):
        try:
            import interplanet_time  # noqa: F401
            cls.skip = False
        except ImportError:
            cls.skip = True

    def setUp(self):
        if self.skip:
            self.skipTest('interplanet_time not installed')

    def test_delay_from_planets(self):
        from interplanet_ltx import delay_from_planets
        # Earth-Mars at J2000 — should be in reasonable range
        lt = delay_from_planets('earth', 'mars', 946728000000)
        self.assertGreater(lt, 100)
        self.assertLess(lt, 2000)

    def test_create_plan_with_real_delay(self):
        from interplanet_ltx import delay_from_planets, create_plan
        lt = delay_from_planets('earth', 'mars', 946728000000)
        plan = create_plan(delay=lt, start='2026-01-01T12:00:00Z')
        self.assertGreater(plan.nodes[1].delay, 100)


class TestConjunctionCheckpoints(unittest.TestCase):
    """Story 28.9 — Conjunction-safe security checkpoints."""

    @classmethod
    def setUpClass(cls):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
            cls.crypto_available = True
        except ImportError:
            cls.crypto_available = False

    def setUp(self):
        if not self.crypto_available:
            self.skipTest('cryptography package not installed')
        host_result = ltx.generate_nik(node_label='Mission Control')
        self.host_nik = host_result['nik']
        self.host_priv = host_result['private_key_b64']
        part_result = ltx.generate_nik(node_label='Mars Hab')
        self.part_nik = part_result['nik']
        self.key_cache = {
            self.host_nik['nodeId']: self.host_nik,
            self.part_nik['nodeId']: self.part_nik,
        }

        # Build a Merkle log with 10 entries
        self.log = ltx.MerkleLog()
        self.log.append({'type': 'TX', 'seq': 1, 'data': 'hello'})
        self.log.append({'type': 'RX', 'seq': 2, 'data': 'world'})
        for i in range(3, 11):
            self.log.append({'seq': i})

        self.merkle_root = self.log.root_hex()
        self.tree_size = self.log.tree_size()
        self.last_seq = {'N0': 147, 'N1': 89}
        self.conj_info = {
            'conjunctionStart': '2026-09-01T00:00:00.000Z',
            'conjunctionEnd':   '2026-09-25T00:00:00.000Z',
        }

    def _make_checkpoint(self):
        return ltx.create_conjunction_checkpoint(
            'plan-cp-001', self.host_nik['nodeId'], self.conj_info,
            self.merkle_root, self.tree_size, self.last_seq, self.host_priv,
        )

    # 1. create_conjunction_checkpoint returns type == 'CONJUNCTION_CHECKPOINT'
    def test_create_checkpoint_type(self):
        cp = self._make_checkpoint()
        self.assertEqual(cp['type'], 'CONJUNCTION_CHECKPOINT')

    # 2. checkpoint['checkpointSig'] is non-empty
    def test_create_checkpoint_sig_non_empty(self):
        cp = self._make_checkpoint()
        self.assertIn('checkpointSig', cp)
        self.assertIsInstance(cp['checkpointSig'], str)
        self.assertGreater(len(cp['checkpointSig']), 0)

    # 3. checkpoint['merkleRoot'] == expectedRoot
    def test_create_checkpoint_merkle_root(self):
        cp = self._make_checkpoint()
        self.assertEqual(cp['merkleRoot'], self.merkle_root)

    # 4. checkpoint['lastSeqPerNode'] contains expected values
    def test_create_checkpoint_last_seq(self):
        cp = self._make_checkpoint()
        self.assertEqual(cp['lastSeqPerNode']['N0'], 147)
        self.assertEqual(cp['lastSeqPerNode']['N1'], 89)

    # 5. verify_conjunction_checkpoint with correct key_cache → {'valid': True}
    def test_verify_checkpoint_valid(self):
        cp = self._make_checkpoint()
        result = ltx.verify_conjunction_checkpoint(cp, self.key_cache)
        self.assertTrue(result['valid'])

    # 6. verify_conjunction_checkpoint with tampered merkleRoot → {'valid': False}
    def test_verify_checkpoint_tampered_root(self):
        cp = self._make_checkpoint()
        tampered = dict(cp)
        tampered['merkleRoot'] = '0' * 64
        result = ltx.verify_conjunction_checkpoint(tampered, self.key_cache)
        self.assertFalse(result['valid'])

    # 7. verify_conjunction_checkpoint with empty key_cache → {'valid': False, 'reason': 'key_not_in_cache'}
    def test_verify_checkpoint_empty_cache(self):
        cp = self._make_checkpoint()
        result = ltx.verify_conjunction_checkpoint(cp, {})
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'key_not_in_cache')

    # 8. create_post_conjunction_queue — enqueue + size work correctly
    def test_queue_enqueue_size(self):
        q = ltx.create_post_conjunction_queue()
        self.assertEqual(q.size(), 0)
        sz1 = q.enqueue({'type': 'TX', 'seq': 1})
        sz2 = q.enqueue({'type': 'RX', 'seq': 2})
        sz3 = q.enqueue({'type': 'TX', 'seq': 3})
        self.assertEqual(sz1, 1)
        self.assertEqual(sz2, 2)
        self.assertEqual(sz3, 3)
        self.assertEqual(q.size(), 3)
        self.assertEqual(len(q.get_queue()), 3)

    # 9. drain(fn) returns correct cleared/rejected counts
    def test_queue_drain(self):
        q = ltx.create_post_conjunction_queue()
        q.enqueue({'type': 'TX', 'seq': 1})
        q.enqueue({'type': 'RX', 'seq': 2})
        q.enqueue({'type': 'TX', 'seq': 3})
        result = q.drain(lambda b: {'valid': b['type'] == 'TX'})
        self.assertEqual(result['cleared'], 2)
        self.assertEqual(result['rejected'], 1)
        self.assertEqual(len(result['rejected_bundles']), 1)
        self.assertEqual(result['rejected_bundles'][0]['type'], 'RX')
        self.assertEqual(q.size(), 0)

    # 10. create_post_conjunction_clear returns type == 'POST_CONJUNCTION_CLEAR'
    def test_create_clear_type(self):
        clear = ltx.create_post_conjunction_clear('plan-cp-001', 42, self.host_priv)
        self.assertEqual(clear['type'], 'POST_CONJUNCTION_CLEAR')
        self.assertEqual(clear['queueProcessed'], 42)
        self.assertIn('clearSig', clear)
        self.assertIsInstance(clear['clearSig'], str)
        self.assertGreater(len(clear['clearSig']), 0)

    # 11. verify_post_conjunction_clear with correct key_cache → valid + signer_node_id
    def test_verify_clear_valid(self):
        clear = ltx.create_post_conjunction_clear('plan-cp-001', 42, self.host_priv)
        result = ltx.verify_post_conjunction_clear(clear, self.key_cache)
        self.assertTrue(result['valid'])
        self.assertEqual(result['signer_node_id'], self.host_nik['nodeId'])

    # 12. verify_post_conjunction_clear with wrong key_cache → {'valid': False}
    def test_verify_clear_wrong_key(self):
        clear = ltx.create_post_conjunction_clear('plan-cp-001', 42, self.host_priv)
        wrong_result = ltx.generate_nik()
        wrong_cache = {wrong_result['nik']['nodeId']: wrong_result['nik']}
        result = ltx.verify_post_conjunction_clear(clear, wrong_cache)
        self.assertFalse(result['valid'])

    # 13. checkpointSignerNodeId is present in checkpoint
    def test_checkpoint_signer_node_id_present(self):
        cp = self._make_checkpoint()
        self.assertIn('checkpointSignerNodeId', cp)
        self.assertEqual(cp['checkpointSignerNodeId'], self.host_nik['nodeId'])

    # 14. checkpoint treeSize matches
    def test_checkpoint_tree_size(self):
        cp = self._make_checkpoint()
        self.assertEqual(cp['treeSize'], self.tree_size)

    # 15. get_queue returns copy (not reference)
    def test_get_queue_returns_copy(self):
        q = ltx.create_post_conjunction_queue()
        q.enqueue({'type': 'TX', 'seq': 1})
        copy = q.get_queue()
        copy.append({'type': 'FAKE'})
        self.assertEqual(q.size(), 1)




class TestBCBConfidentiality(unittest.TestCase):
    """Epic 28.11 — BPSec BCB AES-256-GCM confidentiality tests."""

    def setUp(self):
        try:
            from cryptography.hazmat.primitives.ciphers.aead import AESGCM  # noqa: F401
        except ImportError:
            self.skipTest('cryptography package not installed')

    # 1. encrypt_decrypt_roundtrip
    def test_encrypt_decrypt_roundtrip(self):
        from interplanet_ltx import generate_session_key, encrypt_window, decrypt_window
        key = generate_session_key()
        payload = {'msg': 'hello', 'seq': 1}
        bundle = encrypt_window(payload, key)
        result = decrypt_window(bundle, key)
        self.assertTrue(result['valid'])
        self.assertEqual(result['plaintext']['msg'], 'hello')

    # 2. tag_mismatch: tamper ciphertext
    def test_tag_mismatch(self):
        from interplanet_ltx import generate_session_key, encrypt_window, decrypt_window
        key = generate_session_key()
        bundle = encrypt_window({'data': 'secret'}, key)
        # Tamper the ciphertext (change first character)
        ct = bundle['ciphertext']
        tampered_ct = ('B' if ct[0] == 'A' else 'A') + ct[1:]
        tampered = dict(bundle, ciphertext=tampered_ct)
        result = decrypt_window(tampered, key)
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'tag_mismatch')

    # 3. wrong_key
    def test_wrong_key(self):
        from interplanet_ltx import generate_session_key, encrypt_window, decrypt_window
        key_a = generate_session_key()
        key_b = generate_session_key()
        bundle = encrypt_window({'secret': 42}, key_a)
        result = decrypt_window(bundle, key_b)
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'tag_mismatch')

    # 4. not_bcb
    def test_not_bcb(self):
        from interplanet_ltx import generate_session_key, decrypt_window
        key = generate_session_key()
        result = decrypt_window({'type': 'TX', 'nonce': 'a', 'ciphertext': 'b', 'tag': 'c'}, key)
        self.assertFalse(result['valid'])
        self.assertEqual(result['reason'], 'not_bcb')

    # 5. generateSessionKey_length
    def test_generate_session_key_length(self):
        from interplanet_ltx import generate_session_key
        key = generate_session_key()
        self.assertIsInstance(key, bytes)
        self.assertEqual(len(key), 32)

    # 6. nonce_uniqueness
    def test_nonce_uniqueness(self):
        from interplanet_ltx import generate_session_key, encrypt_window
        key = generate_session_key()
        enc1 = encrypt_window({'x': 1}, key)
        enc2 = encrypt_window({'x': 1}, key)
        self.assertNotEqual(enc1['nonce'], enc2['nonce'])

class TestSessionStateMachine(unittest.TestCase):
    """Epic 68 — session state machine (_session.py)."""

    PLAN = {
        'v': 2, 'title': 'SM Test', 'start': '2026-08-01T12:00:00.000Z',
        'quantum': 5, 'mode': 'LTX-ASYNC',
        'nodes': [
            {'id': 'N0', 'name': 'Earth HQ',  'role': 'HOST',        'delay': 0,   'location': 'earth'},
            {'id': 'N1', 'name': 'Mars Hab',  'role': 'PARTICIPANT', 'delay': 900, 'location': 'mars'},
            {'id': 'N2', 'name': 'Luna Base', 'role': 'PARTICIPANT', 'delay': 2,   'location': 'moon'},
        ],
        'segments': [{'type': 'PLAN_CONFIRM', 'q': 2}, {'type': 'TX', 'q': 2}],
    }
    T0 = 1_000_000

    def _locked_active(self):
        from interplanet_ltx import create_session, transition
        pid = 'PLAN-A'
        ctx = create_session(self.PLAN, pid)
        ctx, _ = transition(ctx, {'type': 'START_LOCK', 'nowMs': self.T0})
        ctx, _ = transition(ctx, {'type': 'PLAN_CONFIRM', 'nowMs': self.T0 + 1, 'nodeId': 'N1', 'planId': pid})
        ctx, _ = transition(ctx, {'type': 'PLAN_CONFIRM', 'nowMs': self.T0 + 2, 'nodeId': 'N2', 'planId': pid})
        ctx, _ = transition(ctx, {'type': 'SESSION_START', 'nowMs': self.T0 + 3})
        return ctx

    def test_draft_and_lock_timeout(self):
        from interplanet_ltx import create_session, lock_timeout_ms
        ctx = create_session(self.PLAN, 'PLAN-A')
        self.assertEqual(ctx['state'], 'DRAFT')
        self.assertEqual(ctx['lockTimeoutMs'], 2 * 900 * 1000)
        self.assertEqual(lock_timeout_ms(self.PLAN), 2 * 900 * 1000)

    def test_full_lock_path(self):
        ctx = self._locked_active()
        self.assertEqual(ctx['state'], 'ACTIVE')
        self.assertEqual(ctx['lock'], 'FULL')

    def test_audit_effect_on_transition(self):
        from interplanet_ltx import create_session, transition
        ctx = create_session(self.PLAN, 'PLAN-A')
        _, effects = transition(ctx, {'type': 'START_LOCK', 'nowMs': self.T0})
        self.assertEqual(effects[0]['kind'], 'audit')
        self.assertEqual(effects[0]['entry']['to'], 'LOCKING')
        self.assertEqual(effects[0]['entry']['type'], 'state_transition')

    def test_mismatch_recorded(self):
        from interplanet_ltx import create_session, transition
        ctx = create_session(self.PLAN, 'PLAN-A')
        ctx, _ = transition(ctx, {'type': 'START_LOCK', 'nowMs': self.T0})
        ctx, effects = transition(ctx, {'type': 'PLAN_CONFIRM', 'nowMs': self.T0 + 1,
                                        'nodeId': 'N1', 'planId': 'PLAN-B'})
        self.assertEqual(ctx['state'], 'LOCKING')
        self.assertIn('N1', ctx['mismatched'])
        self.assertTrue(any(e.get('code') == 'PLANID_MISMATCH' for e in effects))

    def test_timeout_quorum_degraded_and_recovery(self):
        from interplanet_ltx import create_session, transition
        pid = 'PLAN-A'
        ctx = create_session(self.PLAN, pid, quorum=1)
        ctx, _ = transition(ctx, {'type': 'START_LOCK', 'nowMs': self.T0})
        ctx, _ = transition(ctx, {'type': 'PLAN_CONFIRM', 'nowMs': self.T0 + 1, 'nodeId': 'N2', 'planId': pid})
        # 1 ms before timeout: no change
        pre, _ = transition(ctx, {'type': 'TICK', 'nowMs': self.T0 + 2 * 900 * 1000 - 1})
        self.assertEqual(pre['state'], 'LOCKING')
        # at timeout: quorum lock, DEGRADED, subset ordered by ascending delay
        ctx, effects = transition(ctx, {'type': 'TICK', 'nowMs': self.T0 + 2 * 900 * 1000})
        self.assertEqual(ctx['state'], 'DEGRADED')
        self.assertEqual(ctx['lock'], 'QUORUM')
        self.assertEqual(ctx['subset'], ['N0', 'N2'])
        self.assertTrue(any(e['kind'] == 'escalate' for e in effects))
        # late confirm recovers to full LOCKED
        ctx, _ = transition(ctx, {'type': 'PLAN_CONFIRM', 'nowMs': self.T0 + 2_000_000,
                                  'nodeId': 'N1', 'planId': pid})
        self.assertEqual(ctx['state'], 'LOCKED')
        self.assertEqual(ctx['lock'], 'FULL')

    def test_delay_violation_thresholds(self):
        from interplanet_ltx import transition
        ctx = self._locked_active()
        # deviation 120 s: silent
        c1, e1 = transition(ctx, {'type': 'DELAY_MEASURED', 'nowMs': self.T0 + 10,
                                  'nodeId': 'N1', 'measuredDelayS': 1020})
        self.assertEqual(c1['state'], 'ACTIVE')
        self.assertEqual(e1, [])
        # deviation 121 s: warn
        c2, e2 = transition(ctx, {'type': 'DELAY_MEASURED', 'nowMs': self.T0 + 10,
                                  'nodeId': 'N1', 'measuredDelayS': 1021})
        self.assertEqual(c2['state'], 'ACTIVE')
        self.assertTrue(any(e.get('code') == 'DELAY_VIOLATION' for e in e2))
        # deviation 301 s: DEGRADED
        c3, _ = transition(ctx, {'type': 'DELAY_MEASURED', 'nowMs': self.T0 + 10,
                                 'nodeId': 'N1', 'measuredDelayS': 1201})
        self.assertEqual(c3['state'], 'DEGRADED')

    def test_eok_override_and_resume(self):
        from interplanet_ltx import transition
        ctx = self._locked_active()
        hold, _ = transition(ctx, {'type': 'EOK_OVERRIDE', 'nowMs': self.T0 + 10,
                                   'verified': True, 'reason': 'storm'})
        self.assertEqual(hold['state'], 'EMERGENCY_HOLD')
        self.assertEqual(hold['resumeState'], 'ACTIVE')
        rej, eff = transition(ctx, {'type': 'EOK_OVERRIDE', 'nowMs': self.T0 + 10, 'verified': False})
        self.assertEqual(rej['state'], 'ACTIVE')
        self.assertTrue(any(e.get('code') == 'OVERRIDE_REJECTED' for e in eff))
        back, _ = transition(hold, {'type': 'HOST_DECISION', 'nowMs': self.T0 + 20, 'decision': 'resume'})
        self.assertEqual(back['state'], 'ACTIVE')

    def test_amendment_flow(self):
        from interplanet_ltx import transition
        ctx = self._locked_active()
        ctx, _ = transition(ctx, {'type': 'AMENDMENT_PROPOSED', 'nowMs': self.T0 + 10,
                                  'planId': 'PLAN-V3', 'planVersion': 2,
                                  'affectedNodeIds': ['N1']})
        self.assertIsNotNone(ctx['pendingAmendment'])
        self.assertEqual(ctx['pendingAmendment']['timeoutMs'], 2 * 900 * 1000)
        # bad version gap rejected
        _, eff = transition(ctx, {'type': 'AMENDMENT_PROPOSED', 'nowMs': self.T0 + 11,
                                  'planId': 'x', 'planVersion': 4, 'affectedNodeIds': ['N1']})
        self.assertTrue(any(e.get('code') == 'AMENDMENT_REJECTED' for e in eff))
        ctx, eff = transition(ctx, {'type': 'AMENDMENT_CONFIRMED', 'nowMs': self.T0 + 20,
                                    'nodeId': 'N1', 'planId': 'PLAN-V3'})
        self.assertIsNone(ctx['pendingAmendment'])
        self.assertEqual(ctx['planVersion'], 2)
        self.assertEqual(ctx['planId'], 'PLAN-V3')
        self.assertEqual(ctx['sessionRootPlanId'], 'PLAN-A')

    def test_complete_and_ignore_after(self):
        from interplanet_ltx import transition
        ctx = self._locked_active()
        done, _ = transition(ctx, {'type': 'SESSION_END', 'nowMs': self.T0 + 100})
        self.assertEqual(done['state'], 'COMPLETE')
        same, eff = transition(done, {'type': 'SESSION_END', 'nowMs': self.T0 + 101})
        self.assertEqual(same['state'], 'COMPLETE')
        self.assertTrue(any(e.get('code') == 'INVALID_EVENT' for e in eff))

    def test_transition_deterministic(self):
        from interplanet_ltx import create_session, transition
        ctx = create_session(self.PLAN, 'PLAN-A')
        ctx, _ = transition(ctx, {'type': 'START_LOCK', 'nowMs': self.T0})
        ev = {'type': 'TICK', 'nowMs': self.T0 + 2 * 900 * 1000}
        a = transition(ctx, ev)
        b = transition(ctx, ev)
        self.assertEqual(a, b)


class TestAmendmentChains(unittest.TestCase):
    """Epic 68.3 — amendment chains (_amend.py)."""

    PLAN = {
        'v': 2, 'title': 'Chain Test', 'start': '2026-08-01T12:00:00.000Z',
        'quantum': 5, 'mode': 'LTX',
        'nodes': [
            {'id': 'N0', 'name': 'Earth HQ', 'role': 'HOST', 'delay': 0, 'location': 'earth'},
            {'id': 'N1', 'name': 'Mars Hab-01', 'role': 'PARTICIPANT', 'delay': 860, 'location': 'mars'},
        ],
        'segments': [{'type': 'PLAN_CONFIRM', 'q': 2}, {'type': 'TX', 'q': 2},
                     {'type': 'RX', 'q': 2}, {'type': 'BUFFER', 'q': 1}],
    }

    def setUp(self):
        from interplanet_ltx import generate_nik, sign_plan
        try:
            res = generate_nik()
        except ImportError:
            self.skipTest('cryptography/PyNaCl not installed')
        self.nik = res['nik']
        self.priv = res['private_key_b64']
        self.cache = {self.nik['nodeId']: self.nik}
        self.signed_root = sign_plan(self.PLAN, self.priv)

    def test_plan_hash_stable_and_order_insensitive(self):
        from interplanet_ltx import plan_hash
        self.assertRegex(plan_hash(self.PLAN), r'^[0-9a-f]{64}$')
        self.assertEqual(plan_hash({'b': 1, 'a': 2}), plan_hash({'a': 2, 'b': 1}))

    def test_create_amendment_fields(self):
        from interplanet_ltx import create_amendment, plan_hash, make_plan_id
        amd = create_amendment(self.signed_root, {'title': 'Amended'}, self.priv)
        self.assertEqual(amd['plan']['v'], 3)
        self.assertEqual(amd['plan']['planVersion'], 2)
        self.assertEqual(amd['plan']['prevPlanHash'], plan_hash(self.PLAN))
        self.assertNotIn('planVersion', self.PLAN)   # original untouched
        self.assertIn('-v3-', make_plan_id(amd['plan']))

    def test_chain_verification(self):
        from interplanet_ltx import create_amendment, verify_amendment_chain
        amd1 = create_amendment(self.signed_root, {'title': 'Amended'}, self.priv)
        amd2 = create_amendment(amd1, {'quantum': 4}, self.priv)
        self.assertTrue(verify_amendment_chain([self.signed_root, amd1, amd2], self.cache)['valid'])
        self.assertTrue(verify_amendment_chain([self.signed_root], self.cache)['valid'])
        self.assertFalse(verify_amendment_chain([], self.cache)['valid'])
        # skipped link
        self.assertFalse(verify_amendment_chain([self.signed_root, amd2], self.cache)['valid'])

    def test_tamper_and_wrong_signer_rejected(self):
        import copy
        from interplanet_ltx import create_amendment, verify_amendment_chain, generate_nik
        amd1 = create_amendment(self.signed_root, {'title': 'Amended'}, self.priv)
        tampered = copy.deepcopy(amd1)
        tampered['plan']['title'] = 'EVIL'
        self.assertFalse(verify_amendment_chain([self.signed_root, tampered], self.cache)['valid'])
        evil = generate_nik()
        amd_evil = create_amendment(self.signed_root, {'title': 'hijack'}, evil['private_key_b64'])
        self.assertFalse(verify_amendment_chain([self.signed_root, amd_evil], self.cache)['valid'])

    def test_insert_buffer_via_amendment(self):
        from interplanet_ltx import insert_buffer_via_amendment, verify_amendment_chain
        drifted = insert_buffer_via_amendment(self.signed_root, -1, 2, self.priv)
        segs = drifted['plan']['segments']
        self.assertEqual(len(segs), len(self.PLAN['segments']) + 1)
        self.assertEqual(segs[-1], {'type': 'BUFFER', 'q': 2})
        self.assertTrue(verify_amendment_chain([self.signed_root, drifted], self.cache)['valid'])
        mid = insert_buffer_via_amendment(self.signed_root, 1, 1, self.priv)
        self.assertEqual(mid['plan']['segments'][2], {'type': 'BUFFER', 'q': 1})


class TestRegistersAndMerge(unittest.TestCase):
    """Epic 69 — registers (_registers.py) and merge (_merge.py)."""

    SID = 'SID'

    def setUp(self):
        from interplanet_ltx import generate_nik
        try:
            host = generate_nik()
            mars = generate_nik()
        except ImportError:
            self.skipTest('cryptography/PyNaCl not installed')
        self.host_priv = host['private_key_b64']
        self.mars_priv = mars['private_key_b64']
        self.cache = {'N0': host['nik'], 'N1': mars['nik']}

    def _mk(self, etype, content, node_id, seq, ts, priv):
        from interplanet_ltx import create_register_entry
        return create_register_entry(etype, content, self.SID, node_id, seq, ts, priv)

    def _fixture(self):
        q1 = self._mk('question', {'text': 'Water?', 'urgency': 'high'}, 'N1', 1,
                      '2026-08-01T12:01:00.000Z', self.mars_priv)
        qr = self._mk('question_response', {'qid': 'QST-N1-1', 'response': 'OK', 'version': 2},
                      'N0', 1, '2026-08-01T12:05:00.000Z', self.host_priv)
        a1 = self._mk('action', {'description': 'Fix filters', 'owner': 'N1'}, 'N0', 2,
                      '2026-08-01T12:06:00.000Z', self.host_priv)
        au = self._mk('action_update', {'aid': 'ACT-N0-2', 'status': 'DONE', 'version': 2},
                      'N1', 2, '2026-08-01T12:08:00.000Z', self.mars_priv)
        return q1, qr, a1, au

    def test_entry_sign_verify_tamper(self):
        from interplanet_ltx import verify_register_entry
        q1, _, _, _ = self._fixture()
        self.assertEqual(q1['entryId'], 'QST-N1-1')
        self.assertTrue(verify_register_entry(q1, self.cache)['valid'])
        bad = dict(q1, content={'text': 'EVIL'})
        self.assertFalse(verify_register_entry(bad, self.cache)['valid'])
        self.assertEqual(verify_register_entry(q1, {})['reason'], 'key_not_in_cache')

    def test_reducers_and_determinism(self):
        from interplanet_ltx import reduce_questions, reduce_actions
        q1, qr, a1, au = self._fixture()
        entries = [q1, qr, a1, au]
        qs = reduce_questions(entries)
        self.assertEqual(qs['byId']['QST-N1-1']['status'], 'ANSWERED')
        self.assertEqual(qs['byId']['QST-N1-1']['response'], 'OK')
        acts = reduce_actions(entries)
        self.assertEqual(acts['byId']['ACT-N0-2']['status'], 'DONE')
        for shuffled in ([au, q1, a1, qr], [qr, au, q1, a1]):
            self.assertEqual(reduce_questions(shuffled), qs)
            self.assertEqual(reduce_actions(shuffled), acts)

    def test_conflict_lowest_node_wins(self):
        from interplanet_ltx import reduce_questions
        q1, _, _, _ = self._fixture()
        ra = self._mk('question_response', {'qid': 'QST-N1-1', 'response': 'A', 'version': 5},
                      'N0', 7, '2026-08-01T13:00:00.000Z', self.host_priv)
        rb = self._mk('question_response', {'qid': 'QST-N1-1', 'response': 'B', 'version': 5},
                      'N1', 7, '2026-08-01T13:00:00.000Z', self.mars_priv)
        reg1 = reduce_questions([q1, ra, rb])
        reg2 = reduce_questions([q1, rb, ra])
        self.assertEqual(reg1['byId']['QST-N1-1']['response'], 'A')
        self.assertEqual(reg1['byId'], reg2['byId'])
        self.assertIn(rb['entryId'], reg1['superseded'])

    def test_merge_symmetric_and_snapshot(self):
        from interplanet_ltx import (merge_logs, entries_root, run_merge_segment,
                                     verify_register_entry)
        q1, qr, a1, au = self._fixture()
        side_a = [q1, a1, qr]
        side_b = [q1, a1, au]
        m1 = merge_logs(side_a, side_b, self.cache)
        m2 = merge_logs(side_b, side_a, self.cache)
        self.assertEqual(m1['entries'], m2['entries'])
        self.assertEqual(len(m1['entries']), 4)
        self.assertEqual(entries_root(m1['entries']), entries_root(m2['entries']))
        self.assertEqual(m1['rejected'], [])
        res = run_merge_segment(side_a, side_b, self.cache, self.SID, 'N0', 30,
                                '2026-08-01T15:00:00.000Z', self.host_priv)
        snap = res['snapshot']
        self.assertEqual(snap['type'], 'merge_snapshot')
        self.assertTrue(snap['entryId'].startswith('MRG-'))
        self.assertEqual(snap['content']['mergedRoot'], entries_root(res['merged']['entries']))
        self.assertTrue(verify_register_entry(snap, self.cache)['valid'])

    def test_merge_rejects_tampered(self):
        from interplanet_ltx import merge_logs
        q1, qr, a1, au = self._fixture()
        evil = dict(au, content=dict(au['content'], status='REJECTED'))
        m = merge_logs([q1, a1], [evil], self.cache)
        self.assertEqual(len(m['rejected']), 1)

    def test_partition_recovery(self):
        from interplanet_ltx import (order_entries, recover_partition, MerkleLog)
        q1, qr, a1, au = self._fixture()
        shared = order_entries([q1, a1])
        extended = shared + order_entries([au])
        log = MerkleLog()
        for e in extended:
            log.append(e)
        head = log.sign_tree_head(self.mars_priv, 'N1')
        rec = recover_partition(shared, extended, head, self.cache['N1'], self.cache)
        self.assertEqual(rec['action'], 'accept_extension')
        self.assertEqual(len(rec['entries']), 3)
        # diverged sides → deterministic merge
        rec2 = recover_partition(order_entries([q1, a1, qr]), extended, head,
                                 self.cache['N1'], self.cache)
        self.assertEqual(rec2['action'], 'merged')
        self.assertEqual(len(rec2['entries']), 4)
        # lying head → divergent
        bad = dict(head, treeSize=head['treeSize'] + 1)
        rec3 = recover_partition(shared, extended, bad, self.cache['N1'], self.cache)
        self.assertEqual(rec3['action'], 'divergent')
        # wrong signer → divergent
        rec4 = recover_partition(shared, extended, head, self.cache['N0'], self.cache)
        self.assertEqual(rec4['action'], 'divergent')


class TestCborCodec(unittest.TestCase):
    """Story 70.5 — deterministic CBOR (_cbor.py, RFC 8949 §4.2.1 profile)."""

    # RFC 8949 Appendix A vector subset (value, hex)
    VECTORS = [
        (0, '00'),
        (10, '0a'),
        (24, '1818'),
        (100, '1864'),
        (1000, '1903e8'),
        (1000000, '1a000f4240'),
        (-1, '20'),
        (-19, '32'),
        ('', '60'),
        ('a', '6161'),
        ('IETF', '6449455446'),
        ([1, 2, 3], '83010203'),
        ({'a': 1, 'b': [2, 3]}, 'a26161016162820203'),
        (True, 'f5'),
        (False, 'f4'),
        (None, 'f6'),
    ]

    def test_rfc8949_appendix_a_vectors(self):
        from interplanet_ltx import encode_cbor
        for value, expected_hex in self.VECTORS:
            self.assertEqual(encode_cbor(value).hex(), expected_hex,
                             f'vector {value!r}')

    def test_round_trips(self):
        from interplanet_ltx import CborTag, decode_cbor, encode_cbor
        for value, _ in self.VECTORS:
            self.assertEqual(decode_cbor(encode_cbor(value)), value)
        nested = {'x': [1, {'y': b'\x01\x02'}], 'z': None}
        decoded = decode_cbor(encode_cbor(nested))
        self.assertEqual(decoded['x'][0], 1)
        self.assertEqual(decoded['x'][1]['y'], b'\x01\x02')
        self.assertIsNone(decoded['z'])
        tagged = CborTag(18, ['Signature1', b'', 5])
        self.assertEqual(decode_cbor(encode_cbor(tagged)), tagged)

    def test_bool_encodes_as_simple_value_not_int(self):
        # Python bool is an int subclass — must hit major 7, not major 0.
        from interplanet_ltx import encode_cbor
        self.assertEqual(encode_cbor(True).hex(), 'f5')
        self.assertNotEqual(encode_cbor(True).hex(), '01')

    def test_int_map_keys_and_numeric_string_keys(self):
        from interplanet_ltx import encode_cbor
        # {1: -19} — COSE protected header
        self.assertEqual(encode_cbor({1: -19}).hex(), 'a10132')
        # Numeric-looking string keys encode as ints (TS Object.entries parity)
        self.assertEqual(encode_cbor({'1': -19}), encode_cbor({1: -19}))
        # Non-canonical numeric strings stay strings
        self.assertNotEqual(encode_cbor({'01': 1}), encode_cbor({1: 1}))

    def test_map_keys_sorted_by_encoded_bytes(self):
        from interplanet_ltx import encode_cbor
        # int key 4 (0x04) sorts before text key 'a' (0x6161)
        self.assertEqual(encode_cbor({'a': 2, 4: 1}).hex(), 'a20401616102')

    def test_bstr_map_key_decodes_to_base64url(self):
        from interplanet_ltx import decode_cbor
        # {h'01': 2} → key becomes base64url('\x01') = 'AQ'
        self.assertEqual(decode_cbor(bytes.fromhex('a1410102')), {'AQ': 2})

    def test_float_encode_rejected(self):
        from interplanet_ltx import encode_cbor
        with self.assertRaises(ValueError):
            encode_cbor(1.5)

    def test_float_and_simple_decode_rejected(self):
        from interplanet_ltx import decode_cbor
        with self.assertRaises(ValueError):
            decode_cbor(bytes.fromhex('f93c00'))  # half float 1.0
        with self.assertRaises(ValueError):
            decode_cbor(bytes.fromhex('f7'))      # simple value 'undefined'

    def test_indefinite_length_rejected(self):
        from interplanet_ltx import decode_cbor
        with self.assertRaises(ValueError):
            decode_cbor(bytes.fromhex('9f01ff'))  # indefinite array

    def test_trailing_bytes_rejected(self):
        from interplanet_ltx import decode_cbor
        with self.assertRaises(ValueError):
            decode_cbor(bytes.fromhex('0000'))

    def test_truncation_rejected(self):
        from interplanet_ltx import decode_cbor
        for hexstr in ('62', '1903', '8201', ''):
            with self.assertRaises(ValueError):
                decode_cbor(bytes.fromhex(hexstr))


class TestCoseSign1(unittest.TestCase):
    """Story 70.5 — COSE_Sign1 plan signing (_cose.py)."""

    PLAN = {
        'v': 2, 'title': 'COSE Test', 'start': '2026-08-01T12:00:00.000Z',
        'quantum': 5, 'mode': 'LTX',
        'nodes': [
            {'id': 'N0', 'name': 'Earth HQ', 'role': 'HOST', 'delay': 0, 'location': 'earth'},
            {'id': 'N1', 'name': 'Mars Hab-01', 'role': 'PARTICIPANT', 'delay': 860, 'location': 'mars'},
        ],
        'segments': [{'type': 'PLAN_CONFIRM', 'q': 2}],
    }

    def setUp(self):
        from interplanet_ltx import generate_nik
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
        except ImportError:
            self.skipTest('cryptography package not installed')
        res = generate_nik()
        self.nik = res['nik']
        self.priv = res['private_key_b64']
        self.cache = {self.nik['nodeId']: self.nik}

    def test_sign_and_verify_round_trip(self):
        from interplanet_ltx import sign_plan_cose, verify_plan_cose
        env = sign_plan_cose(self.PLAN, self.priv)
        self.assertEqual(env['plan'], self.PLAN)
        self.assertIsInstance(env['coseSign1CborB64'], str)
        self.assertNotIn('=', env['coseSign1CborB64'])  # no padding
        self.assertEqual(verify_plan_cose(env, self.cache), {'valid': True})

    def test_cose_structure_and_kid(self):
        import base64
        from interplanet_ltx import (
            CborTag, COSE_SIGN1_TAG, COSE_ALG_ED25519, decode_cbor, sign_plan_cose,
        )
        from interplanet_ltx import canonical_json
        env = sign_plan_cose(self.PLAN, self.priv)
        decoded = decode_cbor(
            base64.urlsafe_b64decode(env['coseSign1CborB64'] + '=='))
        self.assertIsInstance(decoded, CborTag)
        self.assertEqual(decoded.tag, COSE_SIGN1_TAG)
        protected, unprotected, payload, signature = decoded.value
        self.assertEqual(decode_cbor(protected), {1: COSE_ALG_ED25519})
        # kid = first 16 bytes of SHA-256(raw pub) → b64url == NIK nodeId
        kid_b64 = base64.urlsafe_b64encode(unprotected[4]).rstrip(b'=').decode()
        self.assertEqual(kid_b64, self.nik['nodeId'])
        self.assertEqual(payload.decode('utf-8'), canonical_json(self.PLAN))
        self.assertEqual(len(signature), 64)

    def test_tampered_signature_rejected(self):
        import base64
        from interplanet_ltx import sign_plan_cose, verify_plan_cose
        env = sign_plan_cose(self.PLAN, self.priv)
        raw = bytearray(base64.urlsafe_b64decode(env['coseSign1CborB64'] + '=='))
        raw[-1] ^= 0x01  # flip a signature bit
        tampered = {
            'plan': self.PLAN,
            'coseSign1CborB64':
                base64.urlsafe_b64encode(bytes(raw)).rstrip(b'=').decode(),
        }
        self.assertEqual(verify_plan_cose(tampered, self.cache),
                         {'valid': False, 'reason': 'signature_invalid'})

    def test_payload_mismatch_rejected(self):
        from interplanet_ltx import sign_plan_cose, verify_plan_cose
        env = sign_plan_cose(self.PLAN, self.priv)
        swapped = {'plan': dict(self.PLAN, title='EVIL'),
                   'coseSign1CborB64': env['coseSign1CborB64']}
        self.assertEqual(verify_plan_cose(swapped, self.cache),
                         {'valid': False, 'reason': 'payload_mismatch'})

    def test_missing_envelope_and_unknown_key(self):
        from interplanet_ltx import generate_nik, sign_plan_cose, verify_plan_cose
        self.assertEqual(verify_plan_cose({}, self.cache),
                         {'valid': False, 'reason': 'missing_cose_sign1'})
        env = sign_plan_cose(self.PLAN, self.priv)
        stranger = generate_nik()['nik']
        self.assertEqual(
            verify_plan_cose(env, {stranger['nodeId']: stranger}),
            {'valid': False, 'reason': 'key_not_in_cache'})

    def test_garbage_cbor_rejected(self):
        from interplanet_ltx import verify_plan_cose
        env = {'plan': self.PLAN, 'coseSign1CborB64': 'AAAA'}  # trailing bytes
        self.assertEqual(verify_plan_cose(env, self.cache),
                         {'valid': False, 'reason': 'cbor_decode_failed'})

    def test_verify_plan_any_dispatch(self):
        from interplanet_ltx import sign_plan, sign_plan_cose, verify_plan_any
        cose_env = sign_plan_cose(self.PLAN, self.priv)
        self.assertTrue(verify_plan_any(cose_env, self.cache)['valid'])
        json_env = sign_plan(self.PLAN, self.priv)
        self.assertTrue(verify_plan_any(json_env, self.cache)['valid'])
        self.assertEqual(verify_plan_any({'plan': self.PLAN}, self.cache),
                         {'valid': False, 'reason': 'unknown_envelope'})


class TestBIBEd25519(unittest.TestCase):
    """Story 70.5 — LTX-native Ed25519 BIB (_bib.py additions)."""

    BUNDLE = {'type': 'STATE_UPDATE', 'planId': 'PLAN-1', 'seq': 7,
              'payload': {'phase': 'TX'}}

    def setUp(self):
        from interplanet_ltx import generate_nik
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
        except ImportError:
            self.skipTest('cryptography package not installed')
        res = generate_nik()
        self.nik = res['nik']
        self.priv = res['private_key_b64']

    def test_round_trip(self):
        from interplanet_ltx import add_bib_ed25519, verify_bib_ed25519
        signed = add_bib_ed25519(self.BUNDLE, self.priv)
        self.assertEqual(signed['bib']['securityContext'], 'ltx-ed25519')
        self.assertEqual(signed['bib']['targetBlockNumber'], 0)
        self.assertNotIn('bib', self.BUNDLE)  # input not mutated
        self.assertEqual(verify_bib_ed25519(signed, self.nik), {'valid': True})

    def test_tamper_rejected(self):
        from interplanet_ltx import add_bib_ed25519, verify_bib_ed25519
        signed = add_bib_ed25519(self.BUNDLE, self.priv)
        tampered = dict(signed, seq=8)
        self.assertEqual(verify_bib_ed25519(tampered, self.nik),
                         {'valid': False, 'reason': 'signature_invalid'})

    def test_hmac_verifier_rejects_ed25519_bib(self):
        # Context-confusion defence, direction 1: Ed25519 BIB → verify_bib
        from interplanet_ltx import add_bib_ed25519, generate_bib_key, verify_bib
        signed = add_bib_ed25519(self.BUNDLE, self.priv)
        self.assertEqual(verify_bib(signed, generate_bib_key()),
                         {'valid': False, 'reason': 'context_mismatch'})

    def test_ed25519_verifier_rejects_hmac_bib(self):
        # Context-confusion defence, direction 2: HMAC BIB → verify_bib_ed25519
        from interplanet_ltx import add_bib, generate_bib_key, verify_bib_ed25519
        signed = add_bib(self.BUNDLE, generate_bib_key())
        self.assertEqual(verify_bib_ed25519(signed, self.nik),
                         {'valid': False, 'reason': 'context_mismatch'})

    def test_missing_bib(self):
        from interplanet_ltx import verify_bib_ed25519
        self.assertEqual(verify_bib_ed25519(dict(self.BUNDLE), self.nik),
                         {'valid': False, 'reason': 'missing_bib'})


class TestGlobalSequenceTracker(unittest.TestCase):
    """Story 70.5 — global freshness scope (_security.py, LTX-SECURITY.md §11)."""

    def test_next_seq_scoped_per_sender_and_msg_type(self):
        from interplanet_ltx import GlobalSequenceTracker
        t = GlobalSequenceTracker()
        self.assertEqual(t.next_seq('N0', 'KEY_BUNDLE'), 1)
        self.assertEqual(t.next_seq('N0', 'KEY_BUNDLE'), 2)
        self.assertEqual(t.next_seq('N0', 'KEY_REVOCATION'), 1)  # independent
        self.assertEqual(t.next_seq('N1', 'KEY_BUNDLE'), 1)      # independent

    def test_record_seq_replay_and_gap(self):
        from interplanet_ltx import GlobalSequenceTracker
        t = GlobalSequenceTracker()
        self.assertEqual(t.record_seq('N0', 'KEY_BUNDLE', 1),
                         {'accepted': True, 'gap': False, 'gapSize': 0})
        self.assertEqual(t.record_seq('N0', 'KEY_BUNDLE', 1),
                         {'accepted': False, 'gap': False, 'gapSize': 0,
                          'reason': 'replay'})
        gap = t.record_seq('N0', 'KEY_BUNDLE', 5)
        self.assertEqual(gap, {'accepted': True, 'gap': True, 'gapSize': 3})
        self.assertEqual(t.last_seen_seq('N0', 'KEY_BUNDLE'), 5)
        self.assertEqual(t.last_seen_seq('N0', 'KEY_REVOCATION'), 0)

    def test_snapshot_keys(self):
        from interplanet_ltx import GlobalSequenceTracker
        t = GlobalSequenceTracker()
        t.next_seq('N0', 'KEY_BUNDLE')
        t.record_seq('N1', 'KEY_BUNDLE', 3)
        self.assertEqual(t.snapshot(), {
            'ltx_gseq_N0_KEY_BUNDLE': 1,
            'ltx_gseq_N1_KEY_BUNDLE_rx': 3,
        })

    def test_check_issued_at(self):
        from interplanet_ltx import ISSUED_AT_MAX_AGE_DAYS, check_issued_at
        self.assertEqual(ISSUED_AT_MAX_AGE_DAYS, 30)
        from datetime import datetime, timezone
        now_ms = int(datetime(2026, 7, 1, tzinfo=timezone.utc).timestamp() * 1000)
        # fresh (Z suffix accepted)
        self.assertEqual(check_issued_at('2026-06-25T00:00:00.000Z', now_ms),
                         {'accepted': True})
        # expired (> 30 days old)
        self.assertEqual(check_issued_at('2026-05-01T00:00:00.000Z', now_ms),
                         {'accepted': False, 'reason': 'expired'})
        # custom window
        self.assertEqual(
            check_issued_at('2026-05-01T00:00:00.000Z', now_ms, max_age_days=90),
            {'accepted': True})
        # future-dated (> 1 day ahead)
        self.assertEqual(check_issued_at('2026-07-03T00:00:00.000Z', now_ms),
                         {'accepted': False, 'reason': 'future_dated'})
        # within the 1-day future tolerance
        self.assertEqual(check_issued_at('2026-07-01T12:00:00.000Z', now_ms),
                         {'accepted': True})
        # garbage
        for bad in ('not-a-date', '', None, 12345):
            self.assertEqual(check_issued_at(bad, now_ms),
                             {'accepted': False, 'reason': 'invalid_issued_at'})


class TestKeyBundleFreshness(unittest.TestCase):
    """Story 70.5 — freshness-aware KEY_BUNDLE (_keydist.py, port of TS 70.4)."""

    ISSUED = '2026-06-20T00:00:00.000Z'

    def setUp(self):
        from datetime import datetime, timezone
        from interplanet_ltx import generate_nik
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: F401
        except ImportError:
            self.skipTest('cryptography package not installed')
        host = generate_nik()
        mars = generate_nik()
        self.host_nik = host['nik']
        self.host_priv = host['private_key_b64']
        self.mars_nik = mars['nik']
        self.niks = [self.host_nik, self.mars_nik]
        self.now_ms = int(
            datetime(2026, 7, 1, tzinfo=timezone.utc).timestamp() * 1000)

    def _fresh_bundle(self, seq=1, issued_at=None):
        from interplanet_ltx import create_key_bundle
        return create_key_bundle(
            'PLAN-1', self.niks, self.host_priv,
            sender_node_id=self.host_nik['nodeId'], seq=seq,
            issued_at=issued_at or self.ISSUED)

    def test_fresh_bundle_fields_and_verify(self):
        from interplanet_ltx import GlobalSequenceTracker, verify_and_cache_keys
        bundle = self._fresh_bundle()
        self.assertEqual(bundle['issuedAt'], self.ISSUED)
        self.assertEqual(bundle['timestamp'], self.ISSUED)
        self.assertEqual(bundle['seq'], 1)
        self.assertEqual(bundle['senderNodeId'], self.host_nik['nodeId'])
        cache = verify_and_cache_keys(
            bundle, self.host_nik,
            tracker=GlobalSequenceTracker(), now_ms=self.now_ms)
        self.assertIsNotNone(cache)
        self.assertIn(self.mars_nik['nodeId'], cache)

    def test_replay_rejected(self):
        from interplanet_ltx import GlobalSequenceTracker, verify_and_cache_keys
        bundle = self._fresh_bundle()
        tracker = GlobalSequenceTracker()
        first = verify_and_cache_keys(bundle, self.host_nik,
                                      tracker=tracker, now_ms=self.now_ms)
        self.assertIsNotNone(first)
        replay = verify_and_cache_keys(bundle, self.host_nik,
                                       tracker=tracker, now_ms=self.now_ms)
        self.assertIsNone(replay)

    def test_issued_at_tamper_rejected(self):
        from interplanet_ltx import GlobalSequenceTracker, verify_and_cache_keys
        bundle = self._fresh_bundle()
        tampered = dict(bundle, issuedAt='2026-06-30T00:00:00.000Z')
        self.assertIsNone(verify_and_cache_keys(
            tampered, self.host_nik,
            tracker=GlobalSequenceTracker(), now_ms=self.now_ms))

    def test_stale_bundle_rejected(self):
        from interplanet_ltx import GlobalSequenceTracker, verify_and_cache_keys
        stale = self._fresh_bundle(issued_at='2026-05-01T00:00:00.000Z')
        # Signature is valid, but issuedAt is 61 days before now_ms.
        self.assertIsNotNone(verify_and_cache_keys(stale, self.host_nik))
        self.assertIsNone(verify_and_cache_keys(
            stale, self.host_nik,
            tracker=GlobalSequenceTracker(), now_ms=self.now_ms))

    def test_legacy_bundle_passes_without_enforcement(self):
        from interplanet_ltx import create_key_bundle, verify_and_cache_keys
        legacy = create_key_bundle('PLAN-1', self.niks, self.host_priv)
        self.assertNotIn('issuedAt', legacy)
        cache = verify_and_cache_keys(legacy, self.host_nik)
        self.assertIsNotNone(cache)
        self.assertIn(self.host_nik['nodeId'], cache)

    def test_legacy_bundle_rejected_under_enforcement(self):
        from interplanet_ltx import (
            GlobalSequenceTracker, create_key_bundle, verify_and_cache_keys,
        )
        legacy = create_key_bundle('PLAN-1', self.niks, self.host_priv)
        self.assertIsNone(verify_and_cache_keys(
            legacy, self.host_nik,
            tracker=GlobalSequenceTracker(), now_ms=self.now_ms))


class TestConferenceModeEpic71(unittest.TestCase):
    """Epic 71 conference mode — pair_delay, compute_segments_for,
    build_conference_agenda, prime_time_report, upgrade_plan_to_v3 and the
    per-attendee ICS export (Story 71.4)."""

    def setUp(self):
        self.conf_plan = {
            'v': 2, 'title': 'Solar System Summit',
            'start': '2026-08-01T12:00:00.000Z', 'quantum': 5, 'mode': 'LTX-ASYNC',
            'nodes': [
                {'id': 'N0', 'name': 'Earth HQ',    'role': 'HOST',        'delay': 0,    'location': 'earth'},
                {'id': 'N1', 'name': 'Mars Hab',    'role': 'PARTICIPANT', 'delay': 900,  'location': 'mars'},
                {'id': 'N2', 'name': 'Luna Base',   'role': 'PARTICIPANT', 'delay': 2,    'location': 'moon'},
                {'id': 'N3', 'name': 'Jupiter Obs', 'role': 'PARTICIPANT', 'delay': 2600, 'location': 'jupiter'},
            ],
            'segments': [
                {'type': 'PLAN_CONFIRM', 'q': 2},
                {'type': 'TX', 'q': 3, 'speaker': 'N0', 'label': 'Opening Address'},
                {'type': 'TX', 'q': 4, 'speaker': 'N1', 'label': 'Mars Field Report'},
                {'type': 'RX', 'q': 2},
            ],
        }

    # ── pair_delay ─────────────────────────────────────────────────────────

    def test_pair_delay_host_row(self):
        self.assertEqual(ltx.pair_delay(self.conf_plan, 'N0', 'N1'), 900)

    def test_pair_delay_symmetric(self):
        self.assertEqual(ltx.pair_delay(self.conf_plan, 'N1', 'N0'), 900)

    def test_pair_delay_sum_fallback(self):
        self.assertEqual(ltx.pair_delay(self.conf_plan, 'N1', 'N3'), 3500)

    def test_pair_delay_self_zero(self):
        self.assertEqual(ltx.pair_delay(self.conf_plan, 'N1', 'N1'), 0)

    def test_pair_delay_matrix_wins(self):
        v3 = ltx.upgrade_plan_to_v3(self.conf_plan, delays={'N1|N3': 700})
        self.assertEqual(ltx.pair_delay(v3, 'N3', 'N1'), 700)
        self.assertEqual(ltx.pair_delay(v3, 'N1', 'N3'), 700)

    def test_pair_delay_unknown_node_raises(self):
        with self.assertRaises(ValueError):
            ltx.pair_delay(self.conf_plan, 'N0', 'N9')

    def test_pair_delay_dataclass_input(self):
        plan = create_plan(delay=860)
        self.assertEqual(ltx.pair_delay(plan, 'N0', 'N1'), 860)

    # ── compute_segments_for ───────────────────────────────────────────────

    def test_speaker_sees_transmit(self):
        host_view = ltx.compute_segments_for(self.conf_plan, 'N0')
        self.assertEqual(host_view[1]['perspective'], 'transmit')
        self.assertEqual(host_view[1]['arrivalOffsetS'], 0)

    def test_viewer_sees_receive_with_shift(self):
        mars_view = ltx.compute_segments_for(self.conf_plan, 'N1')
        self.assertEqual(mars_view[1]['perspective'], 'receive')
        self.assertEqual(mars_view[1]['arrivalOffsetS'], 900)
        # Base start of segment 1 is 12:10:00Z; +900 s = 12:25:00Z.
        self.assertEqual(mars_view[1]['start'], '2026-08-01T12:25:00Z')
        self.assertEqual(mars_view[1]['end'], '2026-08-01T12:40:00Z')

    def test_own_segment_unshifted(self):
        mars_view = ltx.compute_segments_for(self.conf_plan, 'N1')
        self.assertEqual(mars_view[2]['perspective'], 'transmit')
        self.assertEqual(mars_view[2]['arrivalOffsetS'], 0)
        self.assertEqual(mars_view[2]['start'], '2026-08-01T12:25:00Z')

    def test_unattributed_neutral(self):
        mars_view = ltx.compute_segments_for(self.conf_plan, 'N1')
        self.assertEqual(mars_view[0]['perspective'], 'neutral')
        self.assertEqual(mars_view[3]['perspective'], 'neutral')
        self.assertNotIn('speaker', mars_view[0])

    def test_label_carried(self):
        mars_view = ltx.compute_segments_for(self.conf_plan, 'N1')
        self.assertEqual(mars_view[1]['label'], 'Opening Address')

    def test_unknown_viewer_raises(self):
        with self.assertRaises(ValueError):
            ltx.compute_segments_for(self.conf_plan, 'N9')

    def test_dataclass_input(self):
        plan = create_plan(delay=600)
        segs = ltx.compute_segments_for(plan, 'N1')
        self.assertEqual(len(segs), len(plan.segments))
        self.assertTrue(all(s['perspective'] == 'neutral' for s in segs))

    # ── build_conference_agenda ────────────────────────────────────────────

    def test_rotation_invariant(self):
        for n in range(3, 6):
            nodes = [
                {'id': f'N{i}', 'name': f'Node {i}',
                 'role': 'HOST' if i == 0 else 'PARTICIPANT',
                 'delay': i * 100, 'location': 'earth'}
                for i in range(n)
            ]
            agenda = ltx.build_conference_agenda(nodes, cycles=n, block_q=2)
            tx = [s for s in agenda if s['type'] == 'TX']
            self.assertEqual(len(tx), n * n, f'N={n} block count')
            openers = {tx[c * n]['speaker'] for c in range(n)}
            self.assertEqual(len(openers), n, f'N={n} openers distinct')
            per_node = {}
            for s in tx:
                per_node[s['speaker']] = per_node.get(s['speaker'], 0) + 1
            self.assertTrue(all(v == n for v in per_node.values()),
                            f'N={n} equal blocks')

    def test_fixed_keeps_plan_order(self):
        agenda = ltx.build_conference_agenda(
            self.conf_plan['nodes'], cycles=2, fairness='fixed')
        tx = [s for s in agenda if s['type'] == 'TX']
        self.assertEqual(tx[0]['speaker'], 'N0')
        self.assertEqual(tx[4]['speaker'], 'N0')

    def test_observers_excluded(self):
        nodes = self.conf_plan['nodes'] + [
            {'id': 'N4', 'name': 'Press', 'role': 'OBSERVER',
             'delay': 0, 'location': 'earth'}]
        agenda = ltx.build_conference_agenda(nodes)
        speakers = {s.get('speaker') for s in agenda if s['type'] == 'TX'}
        self.assertNotIn('N4', speakers)

    def test_labels_applied(self):
        agenda = ltx.build_conference_agenda(
            self.conf_plan['nodes'], labels={'N1': 'Mars Field Report'})
        self.assertTrue(any(s.get('label') == 'Mars Field Report' for s in agenda))

    def test_agenda_framing_defaults(self):
        agenda = ltx.build_conference_agenda(self.conf_plan['nodes'])
        self.assertEqual(agenda[0], {'type': 'PLAN_CONFIRM', 'q': 2})
        self.assertEqual(agenda[-2]['type'], 'MERGE')
        self.assertEqual(agenda[-1]['type'], 'BUFFER')

    def test_no_presenting_nodes_raises(self):
        with self.assertRaises(ValueError):
            ltx.build_conference_agenda(
                [{'id': 'N0', 'name': 'Press', 'role': 'OBSERVER'}])

    def test_agenda_dataclass_nodes(self):
        nodes = [LtxNode(id='N0', name='Earth HQ', role='HOST'),
                 LtxNode(id='N1', name='Mars Hab', role='PARTICIPANT', delay=900)]
        agenda = ltx.build_conference_agenda(nodes)
        tx = [s for s in agenda if s['type'] == 'TX']
        self.assertEqual([s['speaker'] for s in tx], ['N0', 'N1'])

    # ── prime_time_report ──────────────────────────────────────────────────

    def test_rotation_openings_fair(self):
        agenda = ltx.build_conference_agenda(
            self.conf_plan['nodes'], cycles=4, block_q=2)
        plan = {**self.conf_plan, 'segments': agenda}
        report = ltx.prime_time_report(plan)
        self.assertEqual(len(report), 4)
        self.assertTrue(all(r['openings'] == 1 for r in report))
        self.assertTrue(all(0 < r['score'] <= 1 for r in report))

    def test_fixed_openings_unfair(self):
        agenda = ltx.build_conference_agenda(
            self.conf_plan['nodes'], cycles=4, fairness='fixed')
        report = ltx.prime_time_report({**self.conf_plan, 'segments': agenda})
        n0 = next(r for r in report if r['nodeId'] == 'N0')
        self.assertEqual(n0['openings'], 4)
        # Fixed order: N0 always presents first, so it tops the report.
        self.assertEqual(report[0]['nodeId'], 'N0')

    # ── upgrade_plan_to_v3 ─────────────────────────────────────────────────

    def test_upgrade_v3_flag(self):
        v3 = ltx.upgrade_plan_to_v3(self.conf_plan, delays={'N0|N1': 900})
        self.assertEqual(v3['v'], 3)
        self.assertEqual(v3['planVersion'], 1)
        self.assertEqual(v3['delays'], {'N0|N1': 900})

    def test_upgrade_non_mutating(self):
        before = json.dumps(self.conf_plan, sort_keys=True)
        ltx.upgrade_plan_to_v3(self.conf_plan, delays={'N0|N1': 900})
        self.assertEqual(json.dumps(self.conf_plan, sort_keys=True), before)
        self.assertEqual(self.conf_plan['v'], 2)
        self.assertNotIn('delays', self.conf_plan)

    def test_v3_plan_id_infix(self):
        v2_id = make_plan_id(self.conf_plan)
        v3 = ltx.upgrade_plan_to_v3(self.conf_plan, delays={'N0|N1': 900})
        v3_id = make_plan_id(v3)
        self.assertIn('-v3-', v3_id)
        self.assertIn('-v2-', v2_id)
        # v2 planId unchanged post-upgrade (frozen hash).
        self.assertEqual(make_plan_id(self.conf_plan), v2_id)

    def test_upgrade_dataclass_input(self):
        plan = create_plan(delay=860)
        v3 = ltx.upgrade_plan_to_v3(plan, delays={'N0|N1': 860})
        self.assertEqual(v3['v'], 3)
        self.assertEqual(plan.v, 2)  # dataclass untouched

    # ── _plan_as_dict freeze (v2 planId compatibility) ─────────────────────

    def test_plan_as_dict_no_speaker_key_when_unset(self):
        from interplanet_ltx._core import _plan_as_dict
        plan = create_plan(delay=860)
        d = _plan_as_dict(plan)
        for seg in d['segments']:
            self.assertNotIn('speaker', seg)
            self.assertNotIn('label', seg)
            self.assertEqual(list(seg.keys()), ['type', 'q'])

    def test_plan_as_dict_includes_speaker_label_when_set(self):
        from interplanet_ltx._core import _plan_as_dict
        plan = create_plan(segments=[{'type': 'TX', 'q': 2}])
        plan.segments[0].speaker = 'N1'
        plan.segments[0].label = 'Mars'
        d = _plan_as_dict(plan)
        self.assertEqual(list(d['segments'][0].keys()),
                         ['type', 'q', 'speaker', 'label'])

    # ── per-attendee ICS (Story 71.3) ──────────────────────────────────────

    def test_no_arg_ics_single_vevent_and_stable(self):
        plan = create_plan(start='2026-08-01T12:34:56Z', delay=860)
        ics1 = generate_ics(plan)
        ics2 = generate_ics(plan)
        self.assertEqual(ics1.count('BEGIN:VEVENT'), 1)

        def strip_stamp(s):
            return '\r\n'.join(l for l in s.split('\r\n')
                               if not l.startswith('DTSTAMP:'))
        self.assertEqual(strip_stamp(ics1), strip_stamp(ics2))

    def test_viewer_ics_event_per_segment(self):
        ics = generate_ics(self.conf_plan, viewer_node_id='N1')
        self.assertEqual(ics.count('BEGIN:VEVENT'),
                         len(self.conf_plan['segments']))

    def test_viewer_ics_properties(self):
        ics = generate_ics(self.conf_plan, viewer_node_id='N1')
        self.assertIn('LTX-VIEWER:N1', ics)
        self.assertIn('Mars Field Report — you present', ics)
        self.assertIn(
            'Opening Address — Earth HQ, arriving after 15 min light-time', ics)
        self.assertIn('LTX-SPEAKER:N0', ics)

    def test_viewer_ics_pair_delay_lines(self):
        v3 = ltx.upgrade_plan_to_v3(self.conf_plan, delays={'N1|N3': 700})
        ics = generate_ics(v3, viewer_node_id='N1')
        self.assertIn('LTX-DELAY;PAIR=N1|N3:ONEWAY-ASSUMED=700', ics)


if __name__ == '__main__':
    unittest.main()
