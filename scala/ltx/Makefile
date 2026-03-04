SCALAC ?= scalac
SCALA  ?= java

# Scala 3 runtime JARs (needed when running compiled bytecode directly via java)
SCALA_LIB := $(shell find /opt/homebrew/Cellar/scala -name "scala-library-*.jar" 2>/dev/null | head -1)
SCALA3_LIB := $(shell find /opt/homebrew/Cellar/scala -name "scala3-library_3-*.jar" 2>/dev/null | head -1)

SRC  = src/main/scala/Constants.scala src/main/scala/Models.scala src/main/scala/InterplanetLtx.scala src/main/scala/RestClient.scala src/main/scala/Security.scala
TEST = src/test/scala/SecurityTest.scala

.PHONY: test lint clean

test:
	$(SCALAC) -d out/ $(SRC) $(TEST)
	$(SCALA) -cp "out:$(SCALA_LIB):$(SCALA3_LIB)" SecurityTest

lint:
	$(SCALAC) -Xcheck-init $(SRC) -d /tmp/scalac-lint-check 2>&1 | head -20 || true

clean:
	rm -rf out/
