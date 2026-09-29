ELIXIR := $(shell command -v elixir 2>/dev/null)

test:
ifdef ELIXIR
	@echo "==> LTX unit tests"
	elixir -r test/test_helper.exs test/interplanet_ltx_test.exs 2>&1
	@echo "==> Security tests (Epic 29)"
	elixir -r test/test_helper.exs test/security_test.exs 2>&1
	@echo "==> LTX v1.1 core subset tests (Epic 72)"
	elixir -r test/test_helper.exs test/v11_test.exs 2>&1
	@echo "==> JS reference parity tests (issue #27)"
	elixir -r test/test_helper.exs test/parity_test.exs 2>&1
else
	@echo "elixir not installed — skipping tests"
endif

lint:
ifdef ELIXIR
	mix compile --warnings-as-errors --force 2>&1
else
	@echo "elixir not installed — skipping lint"
endif

clean:
	rm -rf _build/ .elixir_ls/

.PHONY: test lint clean
