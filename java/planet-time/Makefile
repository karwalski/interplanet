# Makefile — InterplanetTime Java library
# Requires: Java 16+ (for records)  No Maven/Gradle needed.

JAVAC    = javac
JAVA     = java
SRC_DIR  = src
TEST_DIR = tests
OUT_DIR  = out/classes

.PHONY: all build test clean

all: build test

build:
	@mkdir -p $(OUT_DIR)
	$(JAVAC) -d $(OUT_DIR) $(SRC_DIR)/com/interplanet/time/*.java

test: build
	$(JAVAC) -d $(OUT_DIR) -cp $(OUT_DIR) $(TEST_DIR)/*.java
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	$(JAVA) -cp $(OUT_DIR) TestInterplanetTime
	@echo ""
	@echo "── Running fixture tests ────────────────────────────────────────"
	$(JAVA) -cp $(OUT_DIR) TestFixtures ../c/fixtures/reference.json

clean:
	rm -rf out/
