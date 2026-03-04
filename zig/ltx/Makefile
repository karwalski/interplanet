ZIG ?= zig

.PHONY: build test lint clean

build:
	$(ZIG) build

test:
	$(ZIG) build test

lint:
	$(ZIG) fmt --check src/interplanet_ltx.zig src/unit_test.zig build.zig

clean:
	rm -rf .zig-cache zig-out
