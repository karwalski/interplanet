# Makefile — interplanet_ltx Ruby LTX gem
# Story 33.5 · Ruby 2.6+

.PHONY: test lint build clean

test:
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	ruby -Ilib test/test_interplanet_ltx.rb

lint:
	@ruby -c lib/interplanet_ltx.rb
	@ruby -c lib/interplanet_ltx/constants.rb
	@ruby -c lib/interplanet_ltx/models.rb
	@ruby -c test/test_interplanet_ltx.rb
	@echo "Syntax OK"

build:
	gem build interplanet_ltx.gemspec

clean:
	rm -f *.gem
