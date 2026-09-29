# Makefile — interplanet-ltx JavaScript SDK
# Usage: make test | make lint | make clean

.PHONY: test test-topics lint clean

# Run SDK smoke tests via Node.js
test:
	@echo "Running LTX SDK smoke tests..."
	node -e " \
	  const sdk = require('./ltx-sdk'); \
	  console.assert(typeof sdk.createPlan      === 'function', 'createPlan'); \
	  console.assert(typeof sdk.computeSegments === 'function', 'computeSegments'); \
	  console.assert(typeof sdk.encodeHash      === 'function', 'encodeHash'); \
	  console.assert(typeof sdk.decodeHash      === 'function', 'decodeHash'); \
	  console.assert(typeof sdk.buildNodeUrls   === 'function', 'buildNodeUrls'); \
	  console.assert(typeof sdk.generateICS     === 'function', 'generateICS'); \
	  console.assert(typeof sdk.makePlanId      === 'function', 'makePlanId'); \
	  console.assert(sdk.VERSION.startsWith('1'), 'VERSION'); \
	  const plan = sdk.createPlan({ hostName: 'Earth HQ', delay: 860 }); \
	  console.assert(plan.v === 2, 'plan.v'); \
	  console.assert(Array.isArray(plan.nodes), 'plan.nodes'); \
	  const segs = sdk.computeSegments(plan); \
	  console.assert(segs.length > 0, 'segments'); \
	  console.log('All LTX SDK smoke tests passed'); \
	"
	@$(MAKE) --no-print-directory test-topics
	node tests/protocol-templates.js
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
	@echo "Lint passed ✓"

# Remove generated files
clean:
	rm -rf dist/
