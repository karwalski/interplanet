# Makefile -- interplanet_ltx Lua SDK

LUA ?= lua

.PHONY: test lint clean

test:
	@echo '==> Unit tests'
	$(LUA) test/unit_test.lua
	@echo '==> Security tests (Epic 29)'
	$(LUA) test/security_test.lua
	@echo '==> LTX v1.1 conformance tests (Epic 72)'
	$(LUA) test/v11_test.lua
	@echo '==> JS reference parity tests (issue #27)'
	$(LUA) test/parity_test.lua

# luacheck when installed, else ../lint.sh (luac -p plus a global-access scan).
lint:
	@if command -v luacheck >/dev/null 2>&1; then luacheck src/ test/; else sh ../lint.sh src/*.lua test/*.lua; fi

clean:
	@find . -name "*.luac" -delete
