# Makefile — interplanet-planet-time JavaScript library
# Usage: make build | make test | make build-dist

.PHONY: build test build-dist clean

# Generate dist/ artifacts (ESM, IIFE, TypeScript definitions)
build:
	node build.mjs

# Run library smoke tests via Node.js
test: build
	@echo "Running CJS smoke tests..."
	node -e " \
	  const assert = require('assert'); \
	  const pt = require('./planet-time.js'); \
	  assert(typeof pt.getPlanetTime === 'function', 'CJS: getPlanetTime'); \
	  assert(typeof pt.lightTravelSeconds === 'function', 'CJS: lightTravelSeconds'); \
	  assert(pt.VERSION.startsWith('1'), 'CJS: VERSION'); \
	  if (pt.VERSION !== require('./package.json').version) { \
	    console.error('VERSION ' + pt.VERSION + ' != package.json ' + require('./package.json').version); \
	    process.exit(1); \
	  } \
	  const t = pt.getPlanetTime('mars', new Date('2024-06-15T00:00:00Z')); \
	  assert(t.planet === 'Mars', 'CJS: getPlanetTime returns planet'); \
	  assert(typeof t.isWorkHour === 'boolean', 'CJS: isWorkHour boolean'); \
	  console.log('CJS: all smoke tests passed'); \
	"
	@echo "Running ESM smoke tests..."
	node tests/smoke-esm.mjs
	@echo "All tests passed ✓"

# Prepare package for npm publish (requires npm account)
build-dist: build
	@echo "Dist files ready in dist/"
	@echo "To publish: npm publish --access public"
	@ls -lh dist/

# Remove generated files
clean:
	rm -rf dist/
