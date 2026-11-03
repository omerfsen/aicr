# omerfsen.aicr. Run `make help` for targets.
SHELL := /bin/bash
VENV := .venv
BIN := $(VENV)/bin
PYTHON ?= python3

.PHONY: help dev lint docs build

help:
	@echo "  make dev     venv + dependencies + this repo linked as omerfsen.aicr"
	@echo "  make lint    ansible-lint (production profile) and playbook syntax"
	@echo "  make docs    regenerate docs/variables.md from the argument specs"
	@echo "  make build   build the collection tarball for Galaxy"

$(BIN)/ansible-playbook:
	$(PYTHON) -m venv $(VENV)
	$(BIN)/pip install -q -r requirements.txt

dev: $(BIN)/ansible-playbook
	$(BIN)/ansible-galaxy collection install -r requirements.yml -p .collections
	mkdir -p .collections/ansible_collections/omerfsen
	ln -sfn ../../.. .collections/ansible_collections/omerfsen/aicr

lint: dev
	$(BIN)/ansible-lint --profile production
	$(BIN)/ansible-playbook --syntax-check -i localhost, playbooks/*.yml

docs: dev
	$(BIN)/python tools/gen-variables-doc.py

build: dev
	$(BIN)/ansible-galaxy collection build --force
