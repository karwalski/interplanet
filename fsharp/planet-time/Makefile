BUILD_DIR = InterplanetTime
TEST_DIR  = FixtureTest

build:
	dotnet build $(BUILD_DIR)

test:
	dotnet run --project $(TEST_DIR) 2>&1

lint:
	dotnet build $(BUILD_DIR) -warnaserror
	dotnet build $(TEST_DIR) -warnaserror

pack:
	dotnet pack $(BUILD_DIR) -c Release -o $(BUILD_DIR)/bin/pkg

fixtures:
	dotnet run --project $(TEST_DIR) ../../c/planet-time/fixtures/reference.json 2>&1
