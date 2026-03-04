.PHONY: test lint fixtures instantiate

# Run unit tests
test:
	julia --project=. -e 'import Pkg; Pkg.test()' 2>&1

# Verify the module loads without errors
lint:
	julia --project=. -e 'import Pkg; Pkg.instantiate(); using InterplanetTime; println("InterplanetTime loaded OK")' 2>&1

# Run cross-language fixture validation (requires reference.json)
fixtures:
	julia --project=. fixture_runner.jl ../../c/fixtures/reference.json 2>&1

# Download/instantiate dependencies
instantiate:
	julia --project=. -e 'import Pkg; Pkg.instantiate()' 2>&1
