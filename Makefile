# GHOSTSHELL :: Relay Nine — convenience targets.
# Everything here is a thin wrapper around docker compose; if make is
# not available on your machine, RUNNING.md lists the raw commands.

COMPOSE ?= docker compose
CONTAINER ?= ghostshell

.PHONY: help build up down restart logs play test shell clean rebuild

help:
	@echo 'GHOSTSHELL :: Relay Nine'
	@echo
	@echo '  make build     build the relay image'
	@echo '  make up        start the relay (detached)'
	@echo '  make play      ssh in as level0'
	@echo '  make logs      follow relay logs'
	@echo '  make test      solve every segment and verify isolation'
	@echo '  make down      stop and remove the relay'
	@echo '  make rebuild   rebuild from scratch and restart'
	@echo '  make clean     remove the image and any stale container'
	@echo

build:
	$(COMPOSE) build

up: build
	$(COMPOSE) up -d
	@echo
	@echo 'Relay is up. Play with:  ssh level0@127.0.0.1 -p 2222'
	@echo 'Entry password: ghostshell'

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

play:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    level0@127.0.0.1 -p 2222

test:
	@bash tests/smoke_test.sh

shell:
	docker exec -it $(CONTAINER) bash

rebuild:
	$(COMPOSE) down -v || true
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

clean:
	$(COMPOSE) down -v || true
	-docker rmi ghostshell:1.0
