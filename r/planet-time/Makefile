.PHONY: test fixture lint check clean

test:
	Rscript test/test_unit.R

fixture:
	Rscript test/test_fixtures.R ../../c/planet-time/fixtures/reference.json

lint:
	Rscript -e "source('R/interplanet_time.R'); cat('OK\n')"

clean:
	rm -f *.Rout
	rm -rf .rcheck

# R CMD build + check in .rcheck/ (suggested packages that are not installed
# are reported, not required).
check:
	rm -rf .rcheck && mkdir .rcheck
	cd .rcheck && R CMD build --no-build-vignettes .. && _R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual *.tar.gz
