LUA ?= lua

.PHONY: test fixture lint clean

test:
	$(LUA) test/unit_test.lua 2>&1

fixture:
	$(LUA) test/fixture_runner.lua ../../c/planet-time/fixtures/reference.json 2>&1

# luacheck when installed, else ../lint.sh (luac -p plus a global-access scan).
lint:
	@if command -v luacheck >/dev/null 2>&1; then luacheck src/ test/ --globals arg; else sh ../lint.sh src/*.lua test/*.lua; fi

clean:
	find . -name "*.luac" -delete
