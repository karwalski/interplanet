.PHONY: test lint build clean

SRC  = $(wildcard Sources/InterplanetLTX/*.swift)
TEST = Tests/InterplanetLTXTests/main.swift
BIN  = /tmp/interplanet-ltx-swift-tests

# Prefer macOS 15.x SDK (compatible with Swift 6.1.x compiler).
# Fall back to system default if none found.
_SDK15 := $(firstword $(wildcard \
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk))
ifdef _SDK15
  SDK_FLAG = -sdk $(_SDK15)
else
  SDK_FLAG =
endif

# CryptoKit exists only on Apple platforms. Elsewhere (Linux) the same API
# comes from apple/swift-crypto, which only SwiftPM can fetch, so the
# non-Darwin targets go through `swift build` / `swift run`.
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
test:
	swiftc $(SDK_FLAG) -module-name InterplanetLTX $(SRC) $(TEST) -o $(BIN) 2>&1 && $(BIN)

lint:
	swiftc $(SDK_FLAG) -typecheck $(SRC) 2>&1

build:
	swiftc $(SDK_FLAG) -c $(SRC) -module-name InterplanetLTX 2>&1
else
test:
	swift run InterplanetLTXTests 2>&1

lint:
	swift build 2>&1

build:
	swift build 2>&1
endif

clean:
	rm -f $(BIN)
	rm -rf .build

