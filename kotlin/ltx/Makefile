SRCS = src/main/kotlin/com/interplanet/ltx/Models.kt \
       src/main/kotlin/com/interplanet/ltx/InterplanetLTX.kt \
       src/main/kotlin/com/interplanet/ltx/RestClient.kt \
       src/main/kotlin/com/interplanet/ltx/Security.kt \
       src/test/kotlin/com/interplanet/ltx/InterplanetLTXTest.kt

test:
	@if command -v kotlinc >/dev/null 2>&1; then \
		kotlinc $(SRCS) -include-runtime -d kotlin-ltx.jar && java -jar kotlin-ltx.jar; \
	else echo "kotlinc not in PATH -- skipped"; fi

lint:
	@if command -v kotlinc >/dev/null 2>&1; then \
		mkdir -p /tmp/kotlin-lint-out && \
		kotlinc src/main/kotlin/com/interplanet/ltx/Models.kt \
		        src/main/kotlin/com/interplanet/ltx/InterplanetLTX.kt \
		        src/main/kotlin/com/interplanet/ltx/RestClient.kt \
		        src/main/kotlin/com/interplanet/ltx/Security.kt \
		        -include-runtime -d /tmp/kotlin-lint-out 2>&1; \
	else echo "kotlinc not in PATH -- skipped"; fi

build:
	@if command -v ./gradlew >/dev/null 2>&1; then ./gradlew build; \
	elif command -v kotlinc >/dev/null 2>&1; then kotlinc $(SRCS) -include-runtime -d kotlin-ltx.jar; \
	else echo "No build tool found"; fi

clean:
	rm -f kotlin-ltx.jar
	@if [ -d .gradle ]; then ./gradlew clean 2>/dev/null || true; fi
