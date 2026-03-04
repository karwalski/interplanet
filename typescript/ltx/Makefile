# Makefile — @interplanet/ltx TypeScript LTX SDK
# Story 33.1 · Requires: Node.js 16+  Install dev deps: make install

.PHONY: install build test clean

install:
	npm install

build: install
	npm run build

test: build
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	node tests/run.js

clean:
	rm -rf dist/ node_modules/
