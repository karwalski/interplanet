ZIG ?= zig

.PHONY: build test lint clean

build:
	$(ZIG) build

test:
	$(ZIG) build test

lint:
	$(ZIG) fmt --check src build.zig

clean:
	rm -rf .zig-cache zig-out
