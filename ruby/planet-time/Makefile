# Makefile — interplanet_time Ruby gem
# Requires: Ruby 2.6+

.PHONY: test lint fixture build clean

test:
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	ruby -Ilib test/test_interplanet_time.rb

fixture:
	@echo ""
	@echo "── Running fixture tests ────────────────────────────────────────"
	ruby -Ilib test/fixture_test.rb ../c/fixtures/reference.json

lint:
	ruby -c lib/interplanet_time.rb
	for f in lib/interplanet_time/*.rb; do ruby -c "$$f"; done

build:
	gem build interplanet_time.gemspec

clean:
	rm -f *.gem
