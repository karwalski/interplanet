# Makefile — libinterplanet build system
#
# Targets:
#   make          → build shared + static libraries + test binary
#   make test     → run C unit tests
#   make fixtures → generate fixtures/reference.json from JS reference library
#   make all      → fixtures + build + test
#   make clean    → remove build directory
#
# Prefers CMake if available; falls back to direct cc invocation.

BUILD_DIR := build
NODE      := node
CC        := cc
CFLAGS    := -std=c11 -Wall -Wextra -O2 -Iinclude
LDFLAGS   := -lm

CMAKE     := $(shell command -v cmake 2>/dev/null)

.PHONY: build test fixtures all clean

build:
ifdef CMAKE
	@$(CMAKE) -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
	@$(CMAKE) --build $(BUILD_DIR) --parallel
else
	@mkdir -p $(BUILD_DIR)
	@echo "CMake not found — using direct cc build"
	@$(CC) $(CFLAGS) -fPIC -shared -o $(BUILD_DIR)/libinterplanet.dylib src/libinterplanet.c $(LDFLAGS) 2>/dev/null || \
	 $(CC) $(CFLAGS) -fPIC -shared -o $(BUILD_DIR)/libinterplanet.so    src/libinterplanet.c $(LDFLAGS)
	@$(CC) $(CFLAGS) -c -o $(BUILD_DIR)/libinterplanet.o src/libinterplanet.c
	@ar rcs $(BUILD_DIR)/libinterplanet_s.a $(BUILD_DIR)/libinterplanet.o
	@$(CC) $(CFLAGS) -o $(BUILD_DIR)/test_libinterplanet \
	    tests/test_libinterplanet.c src/libinterplanet.c $(LDFLAGS)
	@echo "Built: $(BUILD_DIR)/test_libinterplanet"
endif

test: build
ifdef CMAKE
	@cd $(BUILD_DIR) && ctest --output-on-failure
else
	@$(BUILD_DIR)/test_libinterplanet
endif

fixtures:
	@$(NODE) tests/generate_fixtures.js

all: fixtures build test

clean:
	@rm -rf $(BUILD_DIR)
