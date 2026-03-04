.PHONY: install test lint build-dist clean

install:
	pip install -e ".[dev]"

test:
	python -m pytest tests/ -v

lint:
	python -m py_compile src/interplanet_time/*.py && echo "Syntax OK"

build-dist:
	python -m build

clean:
	rm -rf dist/ build/ src/interplanet_time.egg-info/ src/interplanet_time/__pycache__ tests/__pycache__
