"""
cross_sdk_verify_py.py — Python SDK verifier side of the cross-SDK integration test.
Reads a JSON blob from stdin (produced by cross_sdk_sign_ts.js or cross_sdk_sign_py.py)
and verifies the signed plan using the Python SDK.

Exits 0 on success, 1 on failure.
"""
import json
import sys
import os

# Ensure we can import interplanet_ltx from the source tree
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python', 'ltx', 'src'))

from interplanet_ltx import verify_plan

data = json.load(sys.stdin)
nik = data.get('nik')
signed_envelope = data.get('signed_envelope')

if not nik or not signed_envelope:
    print('ERROR: input must have nik and signed_envelope fields', file=sys.stderr)
    sys.exit(1)

key_cache = {nik['nodeId']: nik}
result = verify_plan(signed_envelope, key_cache)

if result.get('valid'):
    print('PASS: Python verify_plan → valid=True')
    sys.exit(0)
else:
    reason = result.get('reason', 'unknown')
    print(f'FAIL: Python verify_plan → valid=False, reason={reason}', file=sys.stderr)
    sys.exit(1)
