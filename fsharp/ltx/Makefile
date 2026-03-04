DOTNET := $(shell command -v dotnet 2>/dev/null)

.PHONY: test lint clean

test:
ifdef DOTNET
	dotnet fsi tests/SecurityTest.fsx
else
	@echo "dotnet not installed -- skipping F# security tests"
endif

lint:
ifdef DOTNET
	dotnet build InterplanetLtx.fsproj 2>&1 | tail -5
else
	@echo "dotnet not installed -- skipping lint"
endif

clean:
	rm -rf bin/ obj/
