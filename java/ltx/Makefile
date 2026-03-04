# Makefile — InterplanetLTX Java library
# Story 33.2 · Requires: Java 16+  No Maven/Gradle needed.

JAVAC    = javac
JAVA     = java
SRC_DIR  = src
TEST_DIR = tests
OUT_DIR  = out/classes

.PHONY: all build test clean

all: build test

build:
	@mkdir -p $(OUT_DIR)
	$(JAVAC) -d $(OUT_DIR) $(SRC_DIR)/com/interplanet/ltx/*.java

test: build
	$(JAVAC) -d $(OUT_DIR) -cp $(OUT_DIR) $(TEST_DIR)/TestInterplanetLTX.java
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	$(JAVA) -cp $(OUT_DIR) TestInterplanetLTX

clean:
	rm -rf out/
