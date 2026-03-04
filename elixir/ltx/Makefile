ELIXIR := $(shell command -v elixir 2>/dev/null)
ELIXIRC := $(shell command -v elixirc 2>/dev/null)

test:
ifdef ELIXIR
	@echo "==> Security tests (Epic 29)"
	elixir -r test/test_helper.exs test/security_test.exs 2>&1
else
	@echo "elixir not installed — skipping tests"
endif

lint:
ifdef ELIXIRC
	elixirc lib/**/*.ex --no-docs 2>&1 | head -20
else
	@echo "elixirc not installed — skipping lint"
endif

clean:
	rm -rf _build/ .elixir_ls/

.PHONY: test lint clean
