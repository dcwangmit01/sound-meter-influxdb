.DEFAULT_GOAL := help

SHELL := /usr/bin/env bash

.venv:
	python -m venv .venv
	source .venv/bin/activate && \
	  pip install flake8 yapf pipreqs

.PHONY: deps
deps: .venv  ## Install Dependencies
	@# no-op

.PHONY: format
format:  ## Auto-format and check pep8
	@source .venv/bin/activate && \
	  yapf -i *.py && \
	  flake8 *.py

.PHONY: clean
clean:  ## Clean all temporary files
clean:
	rm -rf .venv

help:  ## Print list of Makefile targets
	@# Taken from https://github.com/spf13/hugo/blob/master/Makefile
	@grep --with-filename -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  cut -d ":" -f2- | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' | sort
