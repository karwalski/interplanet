test:
	julia --project=. test/runtests.jl 2>&1

lint:
	julia -e 'using Pkg; Pkg.activate("."); include("src/InterplanetLtx.jl")' 2>&1

clean:
	rm -rf Manifest.toml

.PHONY: test lint clean
