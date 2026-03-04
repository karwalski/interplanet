# Makefile — interplanet/ltx PHP LTX library
# Story 33.4 · PHP 8.1+ · No Composer required for unit tests.

.PHONY: test lint clean

test:
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	php tests/UnitTest.php

lint:
	@php -l src/autoload.php
	@for f in src/InterplanetLTX/*.php; do php -l "$$f"; done
	@php -l tests/UnitTest.php
	@echo "Lint OK"

clean:
	@echo "Nothing to clean"
