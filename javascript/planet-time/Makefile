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
	  const pt = require('./planet-time.js'); \
	  console.assert(typeof pt.getPlanetTime === 'function', 'CJS: getPlanetTime'); \
	  console.assert(typeof pt.lightTravelSeconds === 'function', 'CJS: lightTravelSeconds'); \
	  console.assert(pt.VERSION.startsWith('1'), 'CJS: VERSION'); \
	  const t = pt.getPlanetTime('mars', new Date('2024-06-15T00:00:00Z')); \
	  console.assert(t.planet === 'Mars', 'CJS: getPlanetTime returns planet'); \
	  console.assert(typeof t.isWorkHour === 'boolean', 'CJS: isWorkHour boolean'); \
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
