BUILD_DIR = InterplanetTime
TEST_DIR  = FixtureTest

build:
	dotnet build $(BUILD_DIR)

test:
	dotnet run --project $(TEST_DIR) 2>&1

lint:
	dotnet build $(BUILD_DIR) 2>&1

fixtures:
	dotnet run --project $(TEST_DIR) ../../c/fixtures/reference.json 2>&1
