ZIG ?= zig

.PHONY: build test lint clean

build:
	$(ZIG) build

test:
	$(ZIG) build test

lint:
	$(ZIG) fmt --check src/interplanet_ltx.zig src/unit_test.zig src/ltx_v11.zig src/v11_test.zig build.zig

clean:
	rm -rf .zig-cache zig-out
