# Makefile — interplanet-ltx JavaScript SDK
# Usage: make test | make lint | make clean

.PHONY: test test-topics lint esm types check-types clean

# Run SDK smoke tests via Node.js
test:
	@echo "Running LTX SDK smoke tests..."
	node -e " \
	  const assert = require('assert'); \
	  const sdk = require('./ltx-sdk'); \
	  assert(typeof sdk.createPlan      === 'function', 'createPlan'); \
	  assert(typeof sdk.computeSegments === 'function', 'computeSegments'); \
	  assert(typeof sdk.encodeHash      === 'function', 'encodeHash'); \
	  assert(typeof sdk.decodeHash      === 'function', 'decodeHash'); \
	  assert(typeof sdk.buildNodeUrls   === 'function', 'buildNodeUrls'); \
	  assert(typeof sdk.generateICS     === 'function', 'generateICS'); \
	  assert(typeof sdk.makePlanId      === 'function', 'makePlanId'); \
	  assert(sdk.VERSION.startsWith('1'), 'VERSION'); \
	  const plan = sdk.createPlan({ hostName: 'Earth HQ', delay: 860 }); \
	  assert(plan.v === 2, 'plan.v'); \
	  assert(Array.isArray(plan.nodes), 'plan.nodes'); \
	  const segs = sdk.computeSegments(plan); \
	  assert(segs.length > 0, 'segments'); \
	  console.log('All LTX SDK smoke tests passed'); \
	"
	@$(MAKE) --no-print-directory test-topics
	node build-esm.mjs --check
	node --input-type=module -e "import * as m from './ltx-sdk.mjs'; import { createRequire } from 'node:module'; \
	  const c = createRequire(import.meta.url)('./ltx-sdk.js'); \
	  const miss = Object.keys(c).filter((k) => m[k] !== c[k]); \
	  if (miss.length) { console.error('ltx-sdk.mjs misses ' + miss); process.exit(1); } \
	  console.log('ESM entry: ' + Object.keys(c).length + ' named exports');"
	node tests/protocol-templates.js
	node tests/multi.js
	node tests/run.js
	@echo "All tests passed ✓"

# EXPERIMENTAL topics extension (docs/LTX-TOPICS-RFC.md, not for production)
test-topics:
	@echo "Running EXPERIMENTAL LTX topics tests..."
	node tests/topics.js

# Static lint via Node.js parse check
lint:
	node --check ltx-sdk.js
	node --check ltx-topics.js
	node --check ltx-protocol-templates.js
	node --check ltx-sdk.mjs
	@echo "Lint passed ✓"

# Regenerate ltx-sdk.mjs (ES module entry) from ltx-sdk.js
esm:
	node build-esm.mjs

# Regenerate ltx-sdk.d.ts from the JSDoc in ltx-sdk.js (needs tsc on PATH)
types:
	node build-types.mjs

# Check ltx-sdk.d.ts is current and usable from a strict TypeScript consumer
check-types:
	@tmp=$$(mktemp -d) && node build-types.mjs $$tmp && \
	  if ! diff -q ltx-sdk.d.ts $$tmp/ltx-sdk.d.ts >/dev/null; then \
	    echo "ltx-sdk.d.ts is stale: run 'make types'"; rm -rf $$tmp; exit 1; fi; \
	  rm -rf $$tmp
	tsc -p tests/types
	@echo "Type declarations OK ✓"

# Remove generated files
clean:
	rm -rf dist/
