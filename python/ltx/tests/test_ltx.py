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
        self.assertEqual(DEFAULT_QUANTUM, 3)

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
        self.assertEqual(total_min(plan), 39)

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
        self.assertIn('LTX-QUANTUM:PT3M', self.ics)

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

if __name__ == '__main__':
    unittest.main()
