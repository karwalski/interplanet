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

lint:
	@command -v luacheck >/dev/null 2>&1 && luacheck src/ test/ || echo "luacheck not installed, skipping lint"

clean:
	@find . -name "*.luac" -delete
