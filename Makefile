.DEFAULT_GOAL := help

SHELL := /usr/bin/env bash

check:  ## Dependencies
	@if ! which jq 2>&1 > /dev/null; then \
	  echo "Please install jq"; \
	fi

.venv:
	python3 -m venv .venv
	source .venv/bin/activate && \
	  pip install flake8 black pipreqs jinja2-cli cython pyyaml yq && \
	  pipreqs ./ --ignore .venv --force && \
	  pip install -r requirements.txt

.PHONY: deps
deps: .venv  ## Install Dependencies

.env: .venv
	echo "INFLUXDB2_USERNAME=admin" > .env
	echo "INFLUXDB2_PASSWORD=$$(openssl rand -hex 16)" >> .env
	echo "INFLUXDB2_ORG=sound" >> .env
	echo "INFLUXDB2_BUCKET=microphone" >> .env
	echo "INFLUXDB2_RETENTION=0" >> .env
	echo "INFLUXDB2_TOKEN=$$(openssl rand -hex 16)" >> .env
	echo "LOCAL_NSRT_DEVICE=$$(find /dev/serial -name usb-Convergence_Instruments_NSRT_mk3_Dev-*)" >> .env
	@# Generate a yaml version of the same file for Jinja2 templating
	cat .env |  awk -F= '{printf "%s: %s\n", $$1, $$2}' > .env.yaml
	if [ -f config.yaml ]; then cat config.yaml >> .env.yaml; fi

config: .env  ## Generate all configuration files
	source .venv/bin/activate && \
	find ./ -name '*.j2' | sed 's/\.[^.]*$$//' | \
	  awk '{print "jinja2 --format yaml " $$1 ".j2 .env.yaml > " $$1}' | sh

.PHONY: format
format:  ## Auto-format and check pep8
	@source .venv/bin/activate && \
	  black --line-length 79 *.py && \
	  flake8 *.py


bootstrap:  ## Create initial configurations for all services
bootstrap: deps config bootstrap-influxdb2 bootstrap-grafana

bootstrap-influxdb2:
	docker compose up -d influxdb2
	@# Wait for influxdb2 to become ready
	while ! docker compose exec -it influxdb2 influx ping 2>&1 | grep -v Error; do \
	  sleep 1; \
	done
	@# Initiate the one time setup.  Error silently if already configured
	source .env && \
	  docker compose exec -it influxdb2 influx setup \
	    --username "$$INFLUXDB2_USERNAME" \
	    --password "$$INFLUXDB2_PASSWORD" \
	    --org "$$INFLUXDB2_ORG" \
	    --bucket "$$INFLUXDB2_BUCKET" \
	    --retention "$$INFLUXDB2_RETENTION" \
	    --token "$$INFLUXDB2_TOKEN" \
	    --force \
	    2>&1 | grep -v Error || true # do not return error if already set up

bootstrap-grafana:
	mkdir -p volumes/grafana/etc/grafana/provisioning/datasources
	mkdir -p volumes/grafana/etc/grafana/provisioning/plugins
	mkdir -p volumes/grafana/etc/grafana/provisioning/notifiers
	mkdir -p volumes/grafana/etc/grafana/provisioning/alerting
	mkdir -p volumes/grafana/etc/grafana/provisioning/dashboards


.PHONY: run
run:  ## Start all services
run: deps config bootstrap
	docker compose up -d

run-logger:  ## Run the logger
	sudo chmod a+rw /dev/serial/by-id/usb-Convergence*
	source .venv/bin/activate && \
	  python3 nsrt-mk3-dev-logger.py

update-git-ignore:  ## Updates .gitignore with jinja2-generated files
	find * -name '*.j2' | sed 's/\.[^.]*$$//' >> .gitignore
	cat .gitignore | sort | uniq > .gitignore.tmp && mv .gitignore.tmp .gitignore

CERTBOT_COMMAND = docker run \
  -v $(PWD)/volumes/certbot/conf:/etc/letsencrypt \
  -v $(PWD)/volumes/certbot/www:/var/www/certbot \
  -p "80:80" --rm \
  certbot/certbot \
  certonly \
  --standalone \
  --non-interactive --agree-tos --expand \
  --renew-with-new-domains \
  --rsa-key-size 4096 \
  --cert-name $$(cat config.yaml | yq -r '.letsencrypt.certname') \
  -m $$(cat config.yaml | yq -r '.letsencrypt.email') \
  -d $$(cat config.yaml | yq -r '.letsencrypt.hosts | join(",")')

certbot-kickstart:  ## Kickstart the certbot configuration. create initial certs and configs so nginx can start
	rm -rf ./volumes/certbot
	@echo "Executing certbot against LetsEncrypt Prod"
	@echo $(CERTBOT_COMMAND)
	@$(CERTBOT_COMMAND)

certbot-kickstart-test:  ## Test the certbot configuration using letsencrypt staging
	@echo "Executing certbot against LetsEncrypt Staging"
	@echo $(CERTBOT_COMMAND) --test-cert
	@$(CERTBOT_COMMAND) --test-cer

.PHONY: clean
clean:  ## Clean all temporary files
clean:
	@# Stop the containers
	docker compose stop || true
	docker compose rm -f || true
	docker network prune --force

	@# Remove Jinja generated files
	find ./ -name '*.j2' | sed 's/\.[^.]*$$//' | xargs rm -f

.PHONY: mrclean
mrclean: clean
	rm -rf .venv
	rm -rf ./volumes/influxdb2/*
	rm -rf ./volumes/grafana/var/lib/grafana/*
	rm -f .env .env.yaml

help:  ## Print list of Makefile targets
	@# Taken from https://github.com/spf13/hugo/blob/master/Makefile
	@grep --with-filename -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  cut -d ":" -f2- | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' | sort
