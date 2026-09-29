test:
	dart test 2>&1

lint:
	dart analyze lib/ 2>&1

fixtures:
	dart run bin/fixture_runner.dart ../../c/planet-time/fixtures/reference.json 2>&1

# Validates the package for pub.dev without uploading (a missing CHANGELOG.md
# is reported as a warning only).
publish-check:
	dart pub publish --dry-run
