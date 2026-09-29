"""Interop driver for python/ltx (see scripts/interop/run.js)."""
import json
import os
import sys

ROOT = os.environ['ROOT']
sys.path.insert(0, os.path.join(ROOT, 'python/ltx/src'))

from interplanet_ltx import (create_plan, encode_hash, make_plan_id,  # noqa: E402
                             upgrade_plan_to_v3)
from interplanet_ltx._encoding import b64dec  # noqa: E402

in_dir, out_dir = sys.argv[1], sys.argv[2]

plan = create_plan(
    title='Réunion Mars 🚀',
    start='2026-03-15T14:00:00.000Z',
    quantum=3,
    mode='LTX-ASYNC',
    nodes=[
        {'id': 'N0', 'name': 'Earth HQ', 'role': 'HOST', 'delay': 0, 'location': 'earth'},
        {'id': 'N1', 'name': 'Mars Hab-01', 'role': 'PARTICIPANT', 'delay': 840, 'location': 'mars'},
        {'id': 'N2', 'name': 'L-1 Gateway', 'role': 'PARTICIPANT', 'delay': 2, 'location': 'moon'},
    ],
    segments=[
        {'type': 'PLAN_CONFIRM', 'q': 2},
        {'type': 'TX', 'q': 3, 'speaker': 'N0', 'label': 'Ouverture: état de la mission'},
        {'type': 'RX', 'q': 3},
        {'type': 'TX', 'q': 2, 'speaker': 'N1', 'label': 'Réponse 🔴'},
        {'type': 'BUFFER', 'q': 1},
    ],
)

# Wire form: the #l= share fragment produced by encode_hash.
wire_v2 = b64dec(encode_hash(plan)[3:])
with open(os.path.join(out_dir, 'wire-v2.json'), 'w', encoding='utf-8') as f:
    f.write(wire_v2)
print('ID_V2', make_plan_id(plan))

v3 = upgrade_plan_to_v3(plan, delays={'N1|N2': 842})
with open(os.path.join(out_dir, 'wire-v3.json'), 'w', encoding='utf-8') as f:
    f.write(json.dumps(v3, ensure_ascii=False, separators=(',', ':')))
print('ID_V3', make_plan_id(v3))
print('NOTE v3 wire via json.dumps (encode_hash takes an LtxPlan v2 only)')

for v in ('2', '3'):
    with open(os.path.join(in_dir, f'js-v{v}.json'), encoding='utf-8') as f:
        print(f'JS_V{v}', make_plan_id(json.loads(f.read())))
