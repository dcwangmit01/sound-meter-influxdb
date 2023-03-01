.DEFAULT_GOAL := help

SHELL := /usr/bin/env bash

# deps: jq, makefile
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

bootstrap-env: .env
.env:
	echo "INFLUXDB2_USERNAME=admin" > .env
	echo "INFLUXDB2_PASSWORD=$$(openssl rand -hex 16)" >> .env
	echo "INFLUXDB2_ORG=sound" >> .env
	echo "INFLUXDB2_BUCKET=microphone" >> .env
	echo "INFLUXDB2_RETENTION=0" >> .env
	echo "INFLUXDB2_TOKEN=$$(openssl rand -hex 16)" >> .env

bootstrap-influxdb2: bootstrap-env  ## Bootstrap Influxdb2 configuration
	docker-compose up -d --wait influxdb2
	source .env && \
	docker-compose exec -it influxdb2 influx setup \
	  --username "$$INFLUXDB2_USERNAME" \
	  --password "$$INFLUXDB2_PASSWORD" \
	  --org "$$INFLUXDB2_ORG" \
	  --bucket "$$INFLUXDB2_BUCKET" \
	  --retention "$$INFLUXDB2_RETENTION" \
	  --token "$$INFLUXDB2_TOKEN" \
	  --force

bootstrap-telegraf:
	docker-compose up -d --wait telegraf

bootstrap-grafana:
	mkdir -p volumes/grafana/etc/grafana/provisioning/datasources
	mkdir -p volumes/grafana/etc/grafana/provisioning/plugins
	mkdir -p volumes/grafana/etc/grafana/provisioning/notifier
	mkdir -p volumes/grafana/etc/grafana/provisioning/alerting
	mkdir -p volumes/grafana/etc/grafana/provisioning/dashboars
	docker-compose up -d --wait grafana

.PHONY: run
run:  # start all services
run: bootstrap-influxdb2 bootstrap-telegraf bootstrap-grafana

.PHONY: clean
clean:  ## Clean all temporary files
clean:
	rm -rf .venv

.PHONY: mrclean
mrclean: clean
	docker-compose stop
	docker-compose rm -f
	rm -rf ./volumes/influxdb2/*
	rm -rf ./volumes/grafana/var/lib/grafana/*
	rm -f .env

help:  ## Print list of Makefile targets
	@# Taken from https://github.com/spf13/hugo/blob/master/Makefile
	@grep --with-filename -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  cut -d ":" -f2- | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' | sort
