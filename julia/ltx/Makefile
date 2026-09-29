test:
	julia --project=. test/runtests.jl 2>&1

# Same suite through the package manager (test deps from [extras]/[targets]).
pkgtest:
	julia --project=. -e 'import Pkg; Pkg.test()' 2>&1

lint:
	julia -e 'using Pkg; Pkg.activate("."); include("src/InterplanetLtx.jl")' 2>&1

clean:
	rm -rf Manifest.toml

.PHONY: test pkgtest lint clean
