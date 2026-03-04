LUA ?= lua

.PHONY: test fixture lint clean

test:
	$(LUA) test/unit_test.lua 2>&1

fixture:
	$(LUA) test/fixture_runner.lua ../../c/planet-time/fixtures/reference.json 2>&1

lint:
	luacheck src/ test/ --globals arg 2>&1 || true

clean:
	find . -name "*.luac" -delete
