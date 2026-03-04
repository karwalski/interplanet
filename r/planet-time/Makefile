.PHONY: test fixture lint clean

test:
	Rscript test/test_unit.R

fixture:
	Rscript test/test_fixtures.R ../c/fixtures/reference.json

lint:
	Rscript -e "source('R/interplanet_time.R'); cat('OK\n')"

clean:
	rm -f *.Rout
