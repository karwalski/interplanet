test:
	Rscript test/test_unit.R 2>&1
	Rscript test/test_parity.R 2>&1

lint:
	Rscript -e 'source("R/constants.R"); source("R/ltx.R"); source("R/parity.R"); cat("OK\n")' 2>&1

clean:
	rm -rf *.Rcheck *.tar.gz .rcheck

.PHONY: test lint check clean

# R CMD build + check in .rcheck/ (suggested packages that are not installed
# are reported, not required).
check:
	rm -rf .rcheck && mkdir .rcheck
	cd .rcheck && R CMD build --no-build-vignettes .. && _R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual *.tar.gz
