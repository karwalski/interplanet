.PHONY: test lint build

test:
	go test -v -run TestAll . 2>&1

lint:
	go vet ./...

build:
	go build ./...
