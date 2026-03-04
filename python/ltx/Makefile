# Makefile — interplanet-ltx Python SDK
# Requires: Python 3.10+  No external runtime dependencies.

PYTHON = python3
SRC    = src/interplanet_ltx

.PHONY: install test lint clean

install:
	pip install -e ".[dev]"

test:
	$(PYTHON) -m pytest tests/ -v

lint:
	$(PYTHON) -m py_compile $(SRC)/*.py && echo "Syntax OK"

clean:
	rm -rf dist/ build/ src/interplanet_ltx.egg-info/ __pycache__ .pytest_cache
	find . -name '*.pyc' -delete
