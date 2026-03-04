ZIG ?= zig

.PHONY: build test lint clean fixture

build:
	$(ZIG) build 2>&1

test:
	$(ZIG) build test 2>&1

fixture: test/fixture_runner.zig src/interplanet_time.zig
	$(ZIG) run test/fixture_runner.zig -- --fixture ../../c/planet-time/fixtures/reference.json 2>&1

lint:
	$(ZIG) fmt --check src/interplanet_time.zig test/unit_test.zig 2>&1

clean:
	rm -rf zig-out .zig-cache
