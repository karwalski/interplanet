test:
	Rscript test/test_unit.R 2>&1

lint:
	Rscript -e 'source("R/constants.R"); source("R/ltx.R"); cat("OK\n")' 2>&1

clean:
	rm -rf *.Rcheck *.tar.gz

.PHONY: test lint clean
