
CONTAINER_ENGINE ?= $(shell which podman >/dev/null 2>&1 && echo podman || echo docker)

.PHONY: test
test:
	@if [ -f manage.py ]; then \
		DJANGO_SETTINGS_MODULE=glitchtip.settings SECRET_KEY=ci python -m unittest apps.alerts.tests.test_webhook_payload_contract -v; \
	fi
	uv run ruff check --no-fix
	uv run ruff format --check
	uv run mypy

build:
	$(CONTAINER_ENGINE) build . -f Dockerfile -t glitchtip
	$(CONTAINER_ENGINE) build . -f Dockerfile.acceptance -t glitchtip-acceptance
