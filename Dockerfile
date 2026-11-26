ARG GLITCHTIP_VERSION=7.0.0

#
# Base image
#
FROM registry.access.redhat.com/ubi9/python-314@sha256:da5ddd149c78475dd51000f984977811f4042fba93e9c3c10f55b3098f513810 AS base
# NOTE: keep this tag in sync with GLITCHTIP_VERSION above. It must stay a
# literal COPY --from= reference (not an ARG or a FROM-aliased stage):
# Konflux's build-cli pre-pull step can't expand ARGs used in COPY --from=,
# and turning this into its own FROM stage makes it show up as a "base image"
# in the SBOM, which trips the base_image_registries.base_image_permitted
# Enterprise Contract policy since this registry isn't Red Hat-trusted.
COPY --from=registry.gitlab.com/glitchtip/glitchtip-frontend:7.0.0@sha256:d0846ea4f72a4b0a026a308633386edc2bfad6fbdf5d86c1acafe5837e67f4a4 /code/LICENSE /licenses/LICENSE

ARG GLITCHTIP_VERSION
ENV GLITCHTIP_VERSION=${GLITCHTIP_VERSION}
LABEL konflux.additional-tags="${GLITCHTIP_VERSION}"


#
# Build and patch Glitchtip
#
FROM base AS builder
ENV \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    # compile bytecode for faster startup
    UV_COMPILE_BYTECODE="true" \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true

COPY --from=ghcr.io/astral-sh/uv:0.13.10@sha256:a3ea1357342c1a4bf9a0c53a3deb1b55379aefa037338d8113d5771efa01774f /uv /bin/uv
COPY --from=registry.gitlab.com/glitchtip/glitchtip-frontend:7.0.0@sha256:d0846ea4f72a4b0a026a308633386edc2bfad6fbdf5d86c1acafe5837e67f4a4 --chown=1001:root /code ./

# Install the required packages
RUN uv sync --frozen --no-group dev

# Our customizations
COPY bin/* ./bin/
COPY appsre ./appsre

# Apply our patches
COPY patches ./patches
# Do not send invitation emails
RUN cat patches/00-skip-user-invitation-process.patch | patch -p1
# add https:// to the s3 endpoint url
RUN cat patches/04-aws-s3-endpoint-url.patch | patch -p1
# Upstream is slowly reverting all my Prometheus metrics. I'm sick of it.
RUN cat patches/09-prometheus-metrics.patch | patch -p1
# Restore prometheus middleware on ingest endpoints for per-view metrics (needed by KEDA autoscaler)
RUN cat patches/08-ingest-prometheus-middleware.patch | patch -p1


#
# Final image
#
FROM base AS prod
ENV PORT=8000
EXPOSE ${PORT}

# Test GLITCHTIP_VERSION is set
RUN if [ -z "${GLITCHTIP_VERSION}" ]; then echo "Error: The environment variable GLITCHTIP_VERSION is not set or empty." >&2; false; fi

# get everything from the builder
COPY --from=builder $APP_ROOT/ $APP_ROOT/

# Collect static files
RUN SECRET_KEY=ci ./manage.py collectstatic --noinput

CMD ["./bin/start.sh"]


#
# Test image
#
FROM prod AS test
COPY --from=ghcr.io/astral-sh/uv:0.13.10@sha256:a3ea1357342c1a4bf9a0c53a3deb1b55379aefa037338d8113d5771efa01774f /uv /bin/uv
ENV \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true

COPY Makefile pyproject.toml ./
COPY acceptance/ ./acceptance/
COPY django-tests/ ./django-tests/
# Directory copy (not per-file) so future django-tests/ additions don't each
# need a new COPY line here. The line above is still needed separately so
# ruff/mypy see the files at their own django-tests/ path too.
COPY django-tests/ apps/alerts/tests/
# Pinned like the other COPY --from= above so Renovate keeps it current:
# this is the real, currently-deployed consumer contract, not a static build
# input, so a Renovate PR bumping this digest is exactly the drift signal we
# want -- the test re-runs against the new contract right there. (Also
# avoids indefinite Docker layer-cache staleness that a floating :latest tag
# would hit.)
COPY --from=quay.io/redhat-services-prod/app-sre-tenant/glitchtip-jira-bridge-main/glitchtip-jira-bridge-main:latest@sha256:2c394ae7ba600d4fa4a7e4ebb503c6eb4afc943914884c6bf8cb79c53fe92505 /opt/app-root/src/glitchtip_jira_bridge/models.py apps/alerts/tests/glitchtip_jira_bridge_models.py
RUN make test
