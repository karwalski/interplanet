DART := $(shell command -v dart 2>/dev/null)

test:
ifdef DART
	dart pub get && dart run test/interplanet_ltx_test.dart 2>&1
else
	@echo "dart not installed -- skipping tests"
endif

lint:
ifdef DART
	dart pub get && dart analyze lib/ test/
else
	@echo "dart not installed -- skipping lint"
endif

clean:
	rm -rf .dart_tool/

.PHONY: test lint publish-check clean

# Validates the package for pub.dev without uploading (a missing CHANGELOG.md
# is reported as a warning only).
publish-check:
	dart pub publish --dry-run
