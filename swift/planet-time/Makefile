.PHONY: build test lint clean

SRC_LIB := $(wildcard Sources/InterplanetTime/*.swift)
SRC_RUN  = Sources/RunTests/main.swift
BIN      = .build/RunTests

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

build:
	mkdir -p .build
	swiftc $(SDK_FLAG) -module-name InterplanetTime $(SRC_LIB) $(SRC_RUN) -o $(BIN) 2>&1
	@echo "Build complete!"

test:
	mkdir -p .build
	swiftc $(SDK_FLAG) -module-name InterplanetTime $(SRC_LIB) $(SRC_RUN) -o $(BIN) 2>&1 && $(BIN)

lint:
	swiftc $(SDK_FLAG) -typecheck $(SRC_LIB) 2>&1

clean:
	rm -rf .build
