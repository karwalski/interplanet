"""
cross_sdk_sign_py.py — Python side of the cross-SDK security integration test.
Generates a NIK, signs a plan, and prints a JSON blob for the TypeScript verifier.
"""
import dataclasses
import json
import sys

# Ensure we can import interplanet_ltx from the source tree
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python', 'ltx', 'src'))

from interplanet_ltx import generate_nik, sign_plan, create_plan

result = generate_nik(valid_days=365, node_label='Python SDK Signer')
nik = result['nik']
private_key_b64 = result['private_key_b64']

plan_obj = create_plan(
    title='Cross-SDK Test',
    start='2026-06-15T09:00:00.000Z',
    delay=800,
)
# sign_plan requires a plain dict (canonical_json does not handle dataclasses)
plan = dataclasses.asdict(plan_obj)

# Normalize float-zero values to int-zero so that canonical JSON matches JS output.
# Python dataclasses store delay as float (0.0); JS JSON.stringify outputs 0.
# This ensures "delay":0 (not "delay":0.0) in the canonical payload.
def _normalise(obj):
    if isinstance(obj, dict):
        return {k: _normalise(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_normalise(v) for v in obj]
    if isinstance(obj, float) and obj == int(obj):
        return int(obj)
    return obj

plan = _normalise(plan)

signed_envelope = sign_plan(plan, private_key_b64)

output = {
    'nik': nik,
    'signed_envelope': signed_envelope,
}

print(json.dumps(output))
