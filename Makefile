
CONTAINER_ENGINE ?= $(shell which podman >/dev/null 2>&1 && echo podman || echo docker)

.PHONY: test
test:
	uv run ruff check --no-fix
	uv run ruff format --check
	uv run mypy

build:
	$(CONTAINER_ENGINE) build . -f Dockerfile -t glitchtip
	$(CONTAINER_ENGINE) build . -f Dockerfile.acceptance -t glitchtip-acceptance
