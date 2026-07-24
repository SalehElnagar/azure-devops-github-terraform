SHELL := /usr/bin/env bash

.PHONY: test validate

test:
	python3 -m unittest discover -s tests -p 'test_*.py'
	bash tests/test_terraform_ci.sh

validate:
	bash scripts/validate.sh
