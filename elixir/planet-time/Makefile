test:
	mix test 2>&1

lint:
	mix compile --warnings-as-errors 2>&1

fixtures:
	mix run fixture_runner/fixture_runner.exs ../../c/planet-time/fixtures/reference.json 2>&1
