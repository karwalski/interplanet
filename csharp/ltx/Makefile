DOTNET := $(shell command -v dotnet 2>/dev/null)
SHELL := /bin/bash

# InterplanetLTX.csproj is the library; tests/InterplanetLTX.Tests.csproj is
# the console test runner that references it.

build:
ifdef DOTNET
	dotnet build InterplanetLTX.csproj
else
	@echo "dotnet not installed — skipping build"
endif

test:
ifdef DOTNET
	dotnet run --project tests 2>&1 | tee /tmp/csharp-ltx-test.log; exit $${PIPESTATUS[0]}
else
	@echo "dotnet not installed — skipping tests"
endif

lint:
ifdef DOTNET
	dotnet build InterplanetLTX.csproj -warnaserror
	dotnet build tests -warnaserror
else
	@echo "dotnet not installed — skipping lint"
endif

pack:
ifdef DOTNET
	dotnet pack InterplanetLTX.csproj -c Release -o bin/pkg
else
	@echo "dotnet not installed, skipping pack"
endif

clean:
	rm -rf bin/ obj/ tests/bin/ tests/obj/

.PHONY: build test lint pack clean
