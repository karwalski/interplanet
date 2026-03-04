DOTNET := $(shell command -v dotnet 2>/dev/null)

build:
ifdef DOTNET
	dotnet build
else
	@echo "dotnet not installed — skipping build"
endif

test: build
ifdef DOTNET
	dotnet run --project . 2>&1 | tee /tmp/csharp-ltx-test.log
else
	@echo "dotnet not installed — skipping tests"
endif

lint:
ifdef DOTNET
	dotnet build --no-restore
else
	@echo "dotnet not installed — skipping lint"
endif

clean:
	rm -rf bin/ obj/

.PHONY: build test lint clean
