ARG GLITCHTIP_VERSION=6.1.6
ARG GLITCHTIP_IMAGE=registry.gitlab.com/glitchtip/glitchtip-frontend:${GLITCHTIP_VERSION}
#
# Base image
#
FROM registry.access.redhat.com/ubi9/python-312:9.7-1778488949@sha256:bf2f5a3cf0c1542d2c90e729bef7e79df746e0331ab7fd19c86e3ff4792dc9f5 AS base
ARG GLITCHTIP_IMAGE
COPY --from=${GLITCHTIP_IMAGE} /code/LICENSE /licenses/LICENSE

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

COPY --from=ghcr.io/astral-sh/uv:0.11.13@sha256:841c8e6fe30a8b07b4478d12d0c608cba6de66102d29d65d1cc423af86051563 /uv /bin/uv
ARG GLITCHTIP_IMAGE
COPY --from=${GLITCHTIP_IMAGE} --chown=1001:root /code ./

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
COPY --from=ghcr.io/astral-sh/uv:0.11.13@sha256:841c8e6fe30a8b07b4478d12d0c608cba6de66102d29d65d1cc423af86051563 /uv /bin/uv
ENV \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true

COPY Makefile pyproject.toml ./
COPY acceptance/ ./acceptance/
RUN make test
