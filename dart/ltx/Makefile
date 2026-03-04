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

.PHONY: test lint clean
