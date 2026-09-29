# Makefile — InterplanetLTX Java library
# Story 33.2 · Requires: Java 16+  No Maven/Gradle needed.

JAVAC    = javac -encoding UTF-8 -Xlint:all
JAVA     = java -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8
SRC_DIR  = src
TEST_DIR = tests
OUT_DIR  = out/classes

.PHONY: all build test clean

all: build test

build:
	@mkdir -p $(OUT_DIR)
	$(JAVAC) -d $(OUT_DIR) $(SRC_DIR)/com/interplanet/ltx/*.java

test: build
	$(JAVAC) -d $(OUT_DIR) -cp $(OUT_DIR) $(TEST_DIR)/TestInterplanetLTX.java $(TEST_DIR)/TestParity.java $(TEST_DIR)/TestPlanIdPrefixes.java
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	$(JAVA) -cp $(OUT_DIR) TestInterplanetLTX
	@echo ""
	@echo "── Running parity tests (spec/golden/plan-ids.json) ────────────"
	$(JAVA) -cp $(OUT_DIR) TestParity ../../spec/golden/plan-ids.json
	@echo ""
	@echo "── Running planId prefix tests (spec/golden/plan-id-prefixes.json) ──"
	$(JAVA) -cp $(OUT_DIR) TestPlanIdPrefixes ../../spec/golden/plan-id-prefixes.json

clean:
	rm -rf out/
