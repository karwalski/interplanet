# Makefile — @interplanet/time TypeScript library
# Requires: Node.js 16+  Install dev deps: make install

.PHONY: install build test clean

install:
	npm install

build: install
	npm run build

test: build
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	node tests/run.js
	@echo ""
	@echo "── Running fixture tests ────────────────────────────────────────"
	node tests/fixtures.js

clean:
	rm -rf dist/ node_modules/
