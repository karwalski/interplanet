# Makefile — interplanet/time PHP library
# Requires: PHP 8.1+, Composer
# Install dev deps: make install

.PHONY: install test lint clean

install:
	composer install

test: install
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	./vendor/bin/phpunit --testdox
	@echo ""
	@echo "── Running fixture tests ────────────────────────────────────────"
	php tests/FixtureTest.php ../../c/planet-time/fixtures/reference.json

lint:
	php -l src/autoload.php
	for f in src/InterplanetTime/*.php; do php -l "$$f"; done
	for f in tests/*.php tests/Unit/*.php; do php -l "$$f"; done

clean:
	rm -rf vendor/ composer.lock
