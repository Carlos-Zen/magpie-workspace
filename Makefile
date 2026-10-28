SHELL := /bin/bash
ENV_FILE ?= .env

.PHONY: help env up down logs admin user image template workspace clean

help:
	@echo "make up         start Coder + PostgreSQL"
	@echo "make admin      create the first Coder admin (reads .env)"
	@echo "make user       create a Coder user; e.g. make user USER=alice EMAIL=alice@example.com"
	@echo "make image      build the workspace image (Claude Code + Magpie + browser)"
	@echo "make template   push the Coder template"
	@echo "make workspace  create a user's workspace; e.g. make workspace SPEC=alice/dev"
	@echo "make down       stop the stack (volumes are preserved)"
	@echo "make clean      stop and delete all volumes (destructive)"

env:
	@test -f $(ENV_FILE) || (cp .env.example $(ENV_FILE) && echo "Created $(ENV_FILE); edit it before continuing.")

up: env
	docker compose --env-file $(ENV_FILE) up -d

down:
	docker compose --env-file $(ENV_FILE) down

logs:
	docker compose --env-file $(ENV_FILE) logs -f --tail=100

admin: up
	./scripts/create-admin.sh

user:
	@test -n "$(USER)" -a -n "$(EMAIL)" || (echo "usage: make user USER=alice EMAIL=alice@example.com" >&2; exit 1)
	./scripts/create-user.sh "$(USER)" "$(EMAIL)"

image:
	./scripts/build-workspace.sh

template:
	./scripts/push-template.sh

workspace:
	@test -n "$(SPEC)" || (echo "usage: make workspace SPEC=alice/dev" >&2; exit 1)
	./scripts/create-workspace.sh "$(SPEC)"

clean:
	docker compose --env-file $(ENV_FILE) down -v
